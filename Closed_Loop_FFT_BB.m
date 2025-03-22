function [allVec,allTs,allTs_marker,allTs_audio] = Closed_Loop_FFT_Binaural()
% Closed-loop algorithm using fft method to detect peak and deliver binaural beats
% allVec: Raw EEG (channel*sample)
% allTs: Timestamp of each sample
% allTs_marker: Timestamp of event markers
% allTs_audio: Timestamp of the sample at which binaural beat was delivered
%% Parameters
elec_interest = [1] % ['Electrode of interest' 'Surrounding electrodes'];
fnative = 10000; % Native sampling rate
fs = 1000; % Processing sampling rate
TrigInt = 3; % Minimum interval between audio bursts (changed from 2 to 3)
win_length = fs/2; % Window length for online processing
targetFreq = [8 13]; % Band of interest in Hz
desired_phase = 0; % Targeted phase
technical_delay = 8; % Technical delay in ms
delay_tolerance = 5; % Delay tolerance in ms

%% Audio parameters for binaural beats
audio_fs = 44100; % Audio sampling rate
left_freq = 420; % Left ear frequency in Hz
right_freq = 460; % Right ear frequency in Hz
beat_duration = 1; % Duration of binaural beat in seconds

% Generate binaural beat signals
t = (0:1/audio_fs:beat_duration-1/audio_fs)';
left_signal = sin(2*pi*left_freq*t);
right_signal = sin(2*pi*right_freq*t);
stereo_signal = [left_signal, right_signal];

% Initialize audio player
try
    audio_player = audioplayer(stereo_signal, audio_fs);
    audio_available = true;
    disp('Audio initialized successfully');
catch
    warning('Failed to initialize audio. Check sound card availability.');
    audio_available = false;
end

%% Initialization
trig_timer = tic; % Used for timing between triggers
downsample = floor(fnative/fs);
num_channel = 5
allVec = nan(num_channel, 100000);
allTs = nan(1,100000);
ft_defaults;

%% Close previously opened inlet streams in case it was not closed properly
try
    inlet.close_stream();
    inlet_marker.close_stream();
catch
end

%% instantiate the library
disp('Loading the library...');
lib = lsl_loadlib();

% resolve a stream...
disp('Resolving an EEG stream...');
result_eeg = {};
while isempty(result_eeg)
    result_eeg = lsl_resolve_byprop(lib,'type','EEG');
end

% Display detailed stream information when resolved
if ~isempty(result_eeg)
    streamInfo = result_eeg{1};
    disp('EEG stream found:');
    disp(['  Name: ' streamInfo.name()]);
    disp(['  Type: ' streamInfo.type()]);
    disp(['  Channel count: ' num2str(streamInfo.channel_count())]);
    disp(['  Sampling rate: ' num2str(streamInfo.nominal_srate()) ' Hz']);
end

% result_marker = {};
% while isempty(result_marker)
%     result_marker = lsl_resolve_byprop(lib,'type','Markers');
% end

% % print all streams
% disp('Available LSL streams:');
% all_streams = lsl_resolve_all(lib);
% for i=1:length(all_streams)
%     disp(['Stream: ' all_streams{i}.name() ' (Type: ' all_streams{i}.type() ')']);
% end
% 
% % look for all streams
% result_eeg = lsl_resolve_all(lib);
% if ~isempty(result_eeg)
%     result_eeg = {result_eeg{1}};  % Use the first available stream
%     disp(['Using stream: ' result_eeg{1}.name() ' (Type: ' result_eeg{1}.type() ')']);
% end
% 
% result_marker = {};
% while isempty(result_marker)
%     result_marker = lsl_resolve_byprop(lib,'type','Markers');
% end

% Try to find a marker stream with a timeout
disp('Looking for a marker stream (with 5-second timeout)...');
result_marker = {};
marker_search_start = tic;
while isempty(result_marker) && toc(marker_search_start) < 5  % 5-second timeout
    result_marker = lsl_resolve_byprop(lib, 'type', 'Markers');
    pause(0.1);  % Small pause to prevent CPU hogging
end

% If no marker stream found, continue with empty marker data
if isempty(result_marker)
    disp('Warning: No marker stream found. Continuing without markers.');
    % Create a dummy inlet that won't be used but prevents errors
    dummy_info = lsl_streaminfo(lib, 'DummyMarkers', 'Markers', 1, 0, 'cf_string', 'DummyID');
    inlet_marker = lsl_inlet(dummy_info);
    allTs_marker = [];  % Initialize empty marker array
else
    disp('Marker stream found. Opening inlet...');
    inlet_marker = lsl_inlet(result_marker{1});
end

% create a new inlet
disp('Opening an inlet...');
inlet = lsl_inlet(result_eeg{1});
% inlet_marker = lsl_inlet(result_marker{1});

%%
disp('Now receiving data...');
sample = 0; % Number of samples received
downsample_idx = 10; % Index used for downsampling
allTs_audio = [];
allTs_marker = [];

while 1
    [vec,ts] = inlet.pull_sample(1);
    [~,ts_marker] = inlet_marker.pull_chunk();
    allTs_marker = [allTs_marker ts_marker];
    if isempty(vec)
        break; % End cycle if didn't receive data within certain time
    end
    if downsample_idx == downsample
        sample = sample+1;
        allVec(:,sample) = vec';
        allTs(:,sample) = ts;
        downsample_idx = 1;
        if sample >= win_length && toc(trig_timer) > TrigInt % Enough samples & enough time between triggers
            if length(elec_interest) == 1
                chunk = allVec(elec_interest,sample-win_length+1:sample)-allVec(num_channel,sample-win_length+1:sample);
            else
                ref = mean(allVec(elec_interest(2:end),sample-win_length+1:sample));
                chunk = allVec(elec_interest(1),sample-win_length+1:sample)-ref;
            end
            chunk_filt = ft_preproc_bandpassfilter(chunk, fs, targetFreq, [], 'fir','twopass');
            
            Xf = fft(chunk_filt,4096);
            [~,idx] = max(abs(Xf));
            f_est = (idx-1)*fs/length(Xf); % Estimated frequency
            phase_est = angle(Xf(idx)); % Estimated phase at the beginning of window
            phase = mod(2*pi*f_est*(win_length-1)/fs+phase_est,2*pi); % Current sample phase
            phase = wrapToPi(phase);
            
            if abs((desired_phase-phase)*fs/f_est/2/pi-technical_delay) <= delay_tolerance
                % Play binaural beats instead of sending TMS trigger
                if audio_available
                    % Create new audioplayer object to ensure fresh playback
                    audio_player = audioplayer(stereo_signal, audio_fs);
                    play(audio_player);
                    trig_timer = tic; % Reset timer after triggering
                    allTs_audio = [allTs_audio ts];
                    disp('Playing binaural beat');
                    
                    % Log additional information about the stimulus
                    fprintf('Beat delivered at phase: %.2f rad, detected frequency: %.2f Hz\n', phase, f_est);
                else
                    disp('Would play binaural beat, but audio is not available');
                    trig_timer = tic;
                end
            end
        end
    else
        downsample_idx = downsample_idx + 1;
    end
end

inlet.close_stream();
inlet_marker.close_stream();
disp('Finished receiving');

% Plot results if any audio was delivered
if ~isempty(allTs_audio)
    figure;
    histogram(mod([allTs_audio-allTs(1)]*f_est, 2*pi), 18);
    title('Distribution of Binaural Beat Delivery Phases');
    xlabel('Phase (rad)');
    ylabel('Count');
    set(gca, 'XLim', [0 2*pi]);
end
end