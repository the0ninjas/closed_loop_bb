function SSAEP_live()
% SSAEP_live - Real-time visualization of Steady State Auditory Evoked Potentials
% induced by binaural beats
%
% This script connects to an EEG LSL stream and a marker stream to visualize
% the SSAEP responses to binaural beats in real-time.
%
% Requirements:
% - LSL library installed and in MATLAB path
% - A running EEG stream
% - Binaural beat markers (from Closed_Loop_FFT_BB.m)
%
% Date: May 2, 2025

%% Parameters
num_channel = 64;                  % Number of EEG channels
elec_interest = [12, 13, 17, 26];  % Electrodes of interest (same as main script)
fnative = 500;                     % Native sampling rate
fs = 250;                          % Processing sampling rate
downsample = floor(fnative/fs);    % Downsampling factor

% Visualization parameters
window_duration = 10;              % Duration of visualization window in seconds
window_samples = window_duration * fs;
buffer_duration = 30;              % Total buffer duration in seconds
buffer_samples = buffer_duration * fs;
update_interval = 0.1;             % Update interval for plots in seconds

% SSAEP analysis parameters
beat_freq = 40;                    % Expected SSAEP frequency (right_freq - left_freq)
analysis_window = 2;               % Analysis window in seconds (for FFT)
analysis_samples = analysis_window * fs;
fft_size = 2^nextpow2(analysis_samples*2); % FFT size

% Frequency bands for visualization
delta = [0.5 4];
theta = [4 8];
alpha = [8 13];
beta = [13 30];
gamma = [30 45];
bands = {delta, theta, alpha, beta, gamma};
band_names = {'Delta', 'Theta', 'Alpha', 'Beta', 'Gamma'};

%% Initialize data buffers
eeg_buffer = zeros(num_channel, buffer_samples);
timestamps_buffer = zeros(1, buffer_samples);
marker_buffer = cell(1, 1000);  % Use cell array for storing string markers
marker_buffer_idx = 0;
marker_timestamps = zeros(1, 1000);
marker_count = 0;

% Counter for buffer position
buffer_pos = 1;
last_update_time = tic;
connected = false;

%% Set up LSL connection
disp('Loading the LSL library...');
try
    lib = lsl_loadlib();
catch
    error('LSL library not found. Please install LSL and add to MATLAB path.');
end

% Resolve EEG stream
disp('Resolving an EEG stream...');
result_eeg = {};
while isempty(result_eeg)
    result_eeg = lsl_resolve_byprop(lib, 'type', 'EEG', 1, 1);
    pause(0.5);
end

% Display EEG stream info
streamInfo = result_eeg{1};
disp('EEG stream found:');
disp(['  Name: ' streamInfo.name()]);
disp(['  Type: ' streamInfo.type()]);
disp(['  Channel count: ' num2str(streamInfo.channel_count())]);
disp(['  Sampling rate: ' num2str(streamInfo.nominal_srate()) ' Hz']);
num_channel = streamInfo.channel_count(); % Update the number of channels

% Re-initialize eeg_buffer with the actual channel count from the stream
eeg_buffer = zeros(num_channel, buffer_samples);

% Look for marker stream (with timeout)
disp('Looking for a marker stream (with 5-second timeout)...');
result_marker = {};
marker_search_start = tic;
while isempty(result_marker) && toc(marker_search_start) < 5
    result_marker = lsl_resolve_byprop(lib, 'type', 'Markers');
    pause(0.1);
end

% Create LSL inlets
disp('Opening EEG inlet...');
inlet_eeg = lsl_inlet(result_eeg{1});
connected = true;

if isempty(result_marker)
    disp('Warning: No marker stream found. Continuing without markers.');
    use_markers = false;
else
    disp('Marker stream found. Opening inlet...');
    inlet_marker = lsl_inlet(result_marker{1});
    use_markers = true;
end

%% Create visualization figure
fig = figure('Name', 'SSAEP Real-time Visualization', ...
             'NumberTitle', 'off', ...
             'Position', [100, 100, 1200, 800], ...
             'Color', 'w', ...
             'CloseRequestFcn', @cleanup_callback);

% Create subplot layout
subplot(3,3,[1,2,4,5]); % Time domain signal
h_time = plot(zeros(1, window_samples));
title('EEG Signal (Filtered)');
xlabel('Time (s)');
ylabel('Amplitude (µV)');
grid on;
xlim([0, window_duration]);
time_ax = gca;

subplot(3,3,3); % SSAEP power
h_ssaep = bar(0, 0);
title('SSAEP Power at Beat Frequency');
xlabel('Time (s)');
ylabel('Power');
ylim([0, 1]);
xlim([-1, 1]);
grid on;

subplot(3,3,6); % Spectrum
h_spectrum = plot(zeros(1, fft_size/2));
title('EEG Spectrum');
xlabel('Frequency (Hz)');
ylabel('Power (dB)');
xlim([0, 50]);
grid on;

subplot(3,3,[7,8,9]); % Spectrogram
h_spectro = imagesc(zeros(50, 50));
title('EEG Spectrogram');
xlabel('Time (s)');
ylabel('Frequency (Hz)');
colorbar;
colormap jet;

% Initialize status text
h_status = uicontrol('Style', 'text', ...
                     'Position', [20, 10, 500, 20], ...
                     'String', 'Status: Initializing...', ...
                     'BackgroundColor', 'w', ...
                     'HorizontalAlignment', 'left');

%% Main loop for real-time processing
disp('Starting real-time visualization...');
set(h_status, 'String', 'Status: Running - Press Ctrl+C or close window to stop');
last_marker_time = 0;
ssaep_powers = [];
ssaep_times = [];

% Initialize filters
[b_notch, a_notch] = iirnotch(50/(fs/2), 30/(fs/2)); % 50Hz notch filter
[b_high, a_high] = butter(4, 0.5/(fs/2), 'high'); % 0.5Hz highpass
[b_low, a_low] = butter(6, 45/(fs/2), 'low'); % 45Hz lowpass

% Preprocessing function
preprocess = @(data) filtfilt(b_low, a_low, filtfilt(b_high, a_high, filtfilt(b_notch, a_notch, data)));

downsample_idx = downsample; % Initialize downsampling index
start_time = tic;

% Initialize spectro_data outside the loop
spectro_data = [];
time_bins = [];

try
    while connected
        % Pull data from LSL
        [chunk, timestamp] = inlet_eeg.pull_sample(0);
        
        % Check for markers with non-blocking pull
        if use_markers
            [marker_chunk, marker_ts] = inlet_marker.pull_chunk();
            if ~isempty(marker_ts)
                % Process markers
                for i = 1:length(marker_ts)
                    % Check if marker_chunk{i} is a string and contains 'BB_'
                    if iscell(marker_chunk) && ischar(marker_chunk{i}) && contains(marker_chunk{i}, 'BB_')
                        marker_count = marker_count + 1;
                        if marker_count <= length(marker_buffer)
                            marker_buffer{marker_count} = marker_chunk{i};
                            marker_timestamps(marker_count) = marker_ts(i);
                            last_marker_time = toc(start_time);
                            
                            % Extract frequency info (if available)
                            marker_parts = strsplit(marker_chunk{i}, '_');
                            detected_freq = NaN;
                            for p = 1:length(marker_parts)
                                if contains(marker_parts{p}, 'freq=')
                                    freq_parts = strsplit(marker_parts{p}, '=');
                                    if length(freq_parts) > 1
                                        detected_freq = str2double(freq_parts{2});
                                        break;
                                    end
                                end
                            end
                            
                            if ~isnan(detected_freq)
                                set(h_status, 'String', sprintf('Status: Binaural beat detected at %.2fs (%.1f Hz)', ...
                                    last_marker_time, detected_freq));
                            else
                                set(h_status, 'String', sprintf('Status: Binaural beat detected at %.2fs', ...
                                    last_marker_time));
                            end
                        end
                    end
                end
            end
        end
        
        % If we have data, process it
        if ~isempty(chunk) && downsample_idx == downsample
            % Update buffer position
            buffer_pos = mod(buffer_pos, buffer_samples) + 1;
            
            % Store data in circular buffer - ensure dimensions match
            % Check if chunk is a row or column vector and transpose if needed
            if size(chunk, 1) == 1
                eeg_buffer(:, buffer_pos) = chunk';  % Transpose row vector to column
            else
                eeg_buffer(:, buffer_pos) = chunk;   % Already a column vector
            end
            timestamps_buffer(buffer_pos) = timestamp;
            
            % Reset downsampling counter
            downsample_idx = 1;
            
            % Update visualization at specified interval
            if toc(last_update_time) >= update_interval
                % Get window of data for visualization
                indices = mod((buffer_pos-window_samples:buffer_pos-1), buffer_samples) + 1;
                data_window = eeg_buffer(:, indices);
                
                % Get ROI data (using the same electrodes as in main script)
                if length(elec_interest) == 1
                    roi_data = data_window(elec_interest,:) - data_window(num_channel,:);
                else
                    ref = mean(data_window(elec_interest(2:end), :));
                    roi_data = data_window(elec_interest(1),:) - ref;
                end
                
                % Preprocess data
                processed_data = preprocess(roi_data);
                
                % Update time domain plot
                time_vec = (0:length(processed_data)-1) / fs;
                set(h_time, 'XData', time_vec, 'YData', processed_data);
                
                % Compute FFT for spectrum
                if buffer_pos > analysis_samples
                    analysis_indices = mod((buffer_pos-analysis_samples:buffer_pos-1), buffer_samples) + 1;
                    analysis_data = eeg_buffer(elec_interest(1), analysis_indices);
                    
                    % Apply window function to reduce spectral leakage
                    windowed_data = analysis_data .* hanning(length(analysis_data))';
                    
                    % Compute FFT
                    Y = fft(windowed_data, fft_size);
                    P2 = abs(Y/analysis_samples);
                    P1 = P2(1:fft_size/2+1);
                    P1(2:end-1) = 2*P1(2:end-1);
                    
                    % Convert to dB for better visualization
                    P_db = 10*log10(P1 + eps);
                    
                    % Frequency vector for plotting
                    f = (0:fft_size/2) * fs / fft_size;
                    
                    % Update spectrum plot
                    set(h_spectrum, 'XData', f, 'YData', P_db);
                    
                    % Find power at beat frequency (40 Hz)
                    beat_idx = find(f >= beat_freq, 1);
                    if ~isempty(beat_idx)
                        % Get power at beat frequency and surrounding ±2 Hz
                        range_start = max(1, beat_idx-round(2*fft_size/fs));
                        range_end = min(length(P1), beat_idx+round(2*fft_size/fs));
                        range_indices = range_start:range_end;
                        ssaep_power = max(P1(range_indices));
                        
                        % Normalize for visualization
                        ssaep_power_norm = min(1, ssaep_power / max(0.1, max(P1)));
                        
                        % Store for trending
                        ssaep_powers = [ssaep_powers, ssaep_power_norm];
                        ssaep_times = [ssaep_times, toc(start_time)];
                        
                        % Keep only the last 60 seconds of data
                        if length(ssaep_times) > 1 && ssaep_times(end) - ssaep_times(1) > 60
                            idx_to_keep = find(ssaep_times > ssaep_times(end) - 60);
                            ssaep_powers = ssaep_powers(idx_to_keep);
                            ssaep_times = ssaep_times(idx_to_keep);
                        end
                        
                        % Update SSAEP power plot
                        bar_width = 0.6;
                        set(h_ssaep, 'XData', 0, 'YData', ssaep_power_norm, 'BarWidth', bar_width);
                        
                        % Update the plot title with the current value
                        title(get(h_ssaep, 'Parent'), sprintf('SSAEP Power: %.2f', ssaep_power_norm));
                    end
                    
                    % Update spectrogram 
                    if isempty(spectro_data)
                        % Get frequencies up to 50 Hz for spectrogram
                        freq_indices = find(f <= 50);
                        spectro_data = zeros(length(freq_indices), 50); % Initialize with zeros
                        time_bins = linspace(0, window_duration, 50);
                    end
                    
                    % Extract frequency data up to 50 Hz and ensure it's a column vector
                    freq_indices = find(f <= 50);
                    freq_data = P_db(freq_indices);
                    freq_data = freq_data(:); % Ensure it's a column vector
                    
                    % Check that dimensions match before concatenation
                    if size(spectro_data, 1) == length(freq_data)
                        % Shift data left and add new column
                        spectro_data = [spectro_data(:, 2:end), freq_data];
                    else
                        % If dimensions don't match, reinitialize spectro_data with correct dimensions
                        spectro_data = zeros(length(freq_indices), 50);
                        spectro_data(:, end) = freq_data;
                    end
                    
                    % Update spectrogram
                    set(h_spectro, 'CData', spectro_data);
                    set(get(h_spectro, 'Parent'), 'YLim', [0 50], 'YDir', 'normal');
                end
                
                % Add marker lines to time domain plot for binaural beat events
                if marker_count > 0
                    % Find markers within the current time window
                    current_time = timestamp;
                    window_start_time = current_time - window_duration;
                    
                    % Clear previous marker lines
                    children = get(time_ax, 'Children');
                    for i = 1:length(children)
                        if strcmp(get(children(i), 'Tag'), 'MarkerLine')
                            delete(children(i));
                        end
                    end
                    
                    % Add new marker lines
                    for i = 1:marker_count
                        if marker_timestamps(i) >= window_start_time && marker_timestamps(i) <= current_time
                            marker_time = (marker_timestamps(i) - window_start_time) / window_duration * window_samples / fs;
                            line([marker_time marker_time], get(time_ax, 'YLim'), 'Color', 'r', 'LineStyle', '--', 'Tag', 'MarkerLine', 'Parent', time_ax);
                        end
                    end
                end
                
                drawnow limitrate;
                last_update_time = tic;
            end
        else
            % Increment downsampling counter or wait a bit
            if ~isempty(chunk)
                downsample_idx = downsample_idx + 1;
            else
                pause(0.001);
            end
        end
    end
catch ME
    set(h_status, 'String', ['Error: ' ME.message]);
    disp(['Error: ' ME.message]);
    disp(getReport(ME, 'extended'));  % Print detailed error report
end

%% Cleanup function for closing figure
function cleanup_callback(~, ~)
    try
        if connected
            disp('Closing LSL connections...');
            inlet_eeg.close_stream();
            if exist('inlet_marker', 'var') && use_markers
                inlet_marker.close_stream();
            end
            connected = false;
        end
        delete(gcf);
    catch
        delete(gcf);
    end
end

end