% openExample('dsp/ReduceLatencyDueToOutputDeviceBufferExample')

% Generate binaural beats with 
% Audio parameters for binaural beats
audio_fs = 44100;                           % Audio sampling rate
left_freq = 420;                            % Left ear frequency in Hz
right_freq = 460;                           % Right ear frequency in Hz
beat_duration = 1;                          % Duration of binaural beat in seconds
buffer_size = 256;                          % Set your desired buffer size

% Generate binaural beat signals with audio Device writer
t = (0:1/audio_fs:beat_duration-1/audio_fs)';
left_signal = sin(2*pi*left_freq*t);
right_signal = sin(2*pi*right_freq*t);
stereo_signal = [left_signal, right_signal];

% Initialize audio player with specific buffer size
try
    % Create audio device writer with variable size support
    deviceWriter = audioDeviceWriter(...
        'SampleRate', audio_fs, ...
        'BufferSize', buffer_size, ...
        'SupportVariableSizeInput', true);  % Allow different sized inputs
    % Keep stereo_signal for play() later
    audio_available = true;
    disp('Audio initialized successfully with buffer size: 256');
catch
    warning('Failed to initialize audio. Check sound card availability.');
    audio_available = false;
end

% Since deviceWriter processes one buffer at a time, for a full signal:
for startIdx = 1:256:length(stereo_signal)
    endIdx = min(startIdx + 255, length(stereo_signal));
    frameToPlay = stereo_signal(startIdx:endIdx, :);
    deviceWriter(frameToPlay);
end

% ouput the buffer latency
bufferLatency = fileReader.SamplesPerFrame/deviceWriter.SampleRate 