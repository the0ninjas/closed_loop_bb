from psychopy import visual, core, event, data, gui
import numpy as np
import random
import os
from datetime import datetime
from pylsl import StreamInfo, StreamOutlet  # Add LSL imports
 
# Experiment setup
exp_name = 'CCPT-V'
exp_info = {'participant': '', 'session': ''}
dlg = gui.DlgFromDict(dictionary=exp_info, title=exp_name)
if not dlg.OK:
    core.quit()  # User pressed cancel

# Parameters setup
num_trials = 10
num_practice = 15
 
# Create data file
data_dir = os.path.join(os.getcwd(), 'data')
if not os.path.exists(data_dir):
    os.makedirs(data_dir)
date_string = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
# Create participant directory
participant_dir = os.path.join(data_dir, f"P{exp_info['participant']}")
if not os.path.exists(participant_dir):
    os.makedirs(participant_dir)
# Create proper filename
filename = os.path.join(participant_dir, f"P{exp_info['participant']}_S{exp_info['session']}_{exp_name}_{date_string}.csv")

# Create LSL outlet for markers
info = StreamInfo(
    name='CCPT-V_Markers',
    type='Markers',
    channel_count=1,
    nominal_srate=0,  # Irregular sampling rate
    channel_format='string',
    source_id=f"CCPT_Visual_{exp_info['participant']}"
)
outlet = StreamOutlet(info)
print("LSL outlet created for sending event markers")
 
# Setup window
win = visual.Window(
    fullscr=True,
    monitor="testMonitor",
    units="cm",
    color=[0, 0, 0]
)
 
# Create stimuli parameters
shapes = ['square', 'circle', 'triangle', 'star', 'diamond', 'rectangle', 'hexagon', 'pentagon']
colors = ['red', 'blue', 'green', 'yellow', 'pink', 'orange']
 
color_rgb = {
    'red': [1, -1, -1],
    'blue': [-1, -1, 1],
    'green': [-1, 1, -1],
    'yellow': [1, 1, -1],
    'pink': [1, 0.6, 0.6],
    'orange': [1, 0.3, -1]
}
 
# Function to create shapes
def create_stimulus(shape_name, color_name):
    color_val = color_rgb[color_name]
    width = random.uniform(1.8, 2.2)
    
    if shape_name == 'square':
        return visual.Rect(win, width=width, height=width, fillColor=color_val, lineColor=None)
    elif shape_name == 'circle':
        return visual.Circle(win, radius=width/2, fillColor=color_val, lineColor=None)
    elif shape_name == 'triangle':
        return visual.Polygon(win, edges=3, radius=width/2, fillColor=color_val, lineColor=None)
    elif shape_name == 'star':
        # Approximate star with polygon
        return visual.Polygon(win, edges=5, radius=width/2, fillColor=color_val, lineColor=None)
    elif shape_name == 'diamond':
        # Alternative approach using a rotated square
        diamond = visual.Rect(win, width=width, height=width, fillColor=color_val, lineColor=None)
        diamond.ori = 45  # Rotate 45 degrees
        return diamond
    elif shape_name == 'rectangle':
        return visual.Rect(win, width=width*1.3, height=width, fillColor=color_val, lineColor=None)
    elif shape_name == 'hexagon':
        return visual.Polygon(win, edges=6, radius=width/2, fillColor=color_val, lineColor=None)
    elif shape_name == 'pentagon':
        return visual.Polygon(win, edges=5, radius=width/2, fillColor=color_val, lineColor=None)
  
# Instructions
instructions = visual.TextStim(
    win,
    text="Press the SPACE BAR when you see a RED SQUARE.\n\n"
         "Do NOT press for any other shapes or colors.\n\n"
         "An example of a RED SQUARE is shown below.\n\n"
         "Press any key to begin practice trials.",
    height=0.7,
    pos=(0, 3)  # Move text up to make room for the square
)

# Create example red square
example_square = visual.Rect(
    win, 
    width=2.0, 
    height=2.0, 
    fillColor=[1, -1, -1],  # Red color
    lineColor=None,
    pos=(0, -3)  # Position below the text
)

# Display instructions and example square
instructions.draw()
example_square.draw()
win.flip()
outlet.push_sample(["instructions_with_example_displayed"])  # Mark instructions onset
event.waitKeys()
outlet.push_sample(["instructions_acknowledged"])  # Mark instructions acknowledged
 
# Create trial sequence
def create_trial_sequence(num_trials, is_practice=False):
    trials = []
    
    # Calculate trial counts
    target_count = int(num_trials * 0.30)  # Red square - 30%
    non_red_square_count = int(num_trials * 0.175)  # Non-red square - 17.5%
    red_non_square_count = int(num_trials * 0.175)  # Red non-square - 17.5%
    other_count = num_trials - target_count - non_red_square_count - red_non_square_count  # ~35%
    
    # Create trials
    for _ in range(target_count):
        trials.append({'shape': 'square', 'color': 'red', 'is_target': True})
    
    # Non-red squares
    for _ in range(non_red_square_count):
        color = random.choice([c for c in colors if c != 'red'])
        trials.append({'shape': 'square', 'color': color, 'is_target': False})
    
    # Red non-squares
    for _ in range(red_non_square_count):
        shape = random.choice([s for s in shapes if s != 'square'])
        trials.append({'shape': shape, 'color': 'red', 'is_target': False})
    
    # Other stimuli (neither red nor square)
    for _ in range(other_count):
        shape = random.choice([s for s in shapes if s != 'square'])
        color = random.choice([c for c in colors if c != 'red'])
        trials.append({'shape': shape, 'color': color, 'is_target': False})
    
    # Shuffle trials
    random.shuffle(trials)
    
    # Assign ISIs
    isis = [0.400, 0.600, 0.800, 1]
    isi_count = len(trials) // len(isis)
    isi_list = []
    for isi in isis:
        isi_list.extend([isi] * isi_count)
    
    # Add extra ISIs if needed
    while len(isi_list) < len(trials):
        isi_list.append(random.choice(isis))
    
    # Shuffle ISIs
    random.shuffle(isi_list)
    
    # Assign ISIs to trials
    for i, trial in enumerate(trials):
        trial['isi'] = isi_list[i]
    
    return trials
 
# Create clock
clock = core.Clock()
exp_timer = core.Clock()
 
# Data storage
exp_data = []
 
# Run practice trials
practice_message = visual.TextStim(win, text="Practice trials will now begin.\n\nPress any key to continue.")
practice_message.draw()
win.flip()
outlet.push_sample(["practice_instructions_displayed"])
event.waitKeys()
outlet.push_sample(["practice_start"])

practice_trials = create_trial_sequence(num_practice, is_practice=True)
practice_trial_num = 0

for trial in practice_trials:
    practice_trial_num += 1
    
    # Inter-stimulus interval
    win.flip()  # Show blank screen
    outlet.push_sample([f"practice_isi_{practice_trial_num}"])
    core.wait(trial['isi'])
    
    # Show stimulus
    stim = create_stimulus(trial['shape'], trial['color'])
    stim.draw()
    win.flip()
    
    # Send stimulus marker
    is_target_str = "target" if trial['is_target'] else "non_target"
    outlet.push_sample([f"practice_stim_{practice_trial_num}_{trial['shape']}_{trial['color']}_{is_target_str}"])
    
    # Record response
    response = None
    rt = None
    
    trial_clock = core.Clock()
    keys = event.waitKeys(maxWait=0.200, timeStamped=trial_clock, keyList=['space', 'escape'])
    
    # Mark stimulus offset
    win.flip()  # Clear screen
    outlet.push_sample([f"practice_stim_offset_{practice_trial_num}"])
    
    if keys:
        if 'escape' in [k[0] for k in keys]:
            outlet.push_sample(["practice_aborted"])
            win.close()
            core.quit()
        
        response = 'space' in [k[0] for k in keys]
        rt = keys[0][1]
        
        if response:
            outlet.push_sample([f"practice_response_{practice_trial_num}_{rt}"])
 
outlet.push_sample(["practice_complete"])

# Transition from practice to main trials
main_message = visual.TextStim(
    win,
    text="Practice complete.\n\nThe main experiment will now begin.\n\n"
         "Remember: Press SPACE BAR only for RED SQUARES.\n\n"
         "Press any key to start.",
    height=0.7
)
main_message.draw()
win.flip()
outlet.push_sample(["main_instructions_displayed"])
event.waitKeys()
outlet.push_sample(["main_experiment_start"])
 
# Data file setup
data_file = open(f"{filename}.csv", 'w')
data_file.write("trial,shape,color,is_target,isi,response,rt,correct\n")
 
# Run experimental trials
trials = create_trial_sequence(num_trials)
trial_num = 0
 
for trial in trials:
    trial_num += 1
    
    # Show fixation
    win.flip()
    outlet.push_sample([f"isi_{trial_num}"])
    core.wait(trial['isi'])
    
    # Show stimulus
    stim = create_stimulus(trial['shape'], trial['color'])
    stim.draw()
    win.flip()
    
    # Send stimulus marker with detailed information
    is_target_str = "target" if trial['is_target'] else "non_target"
    outlet.push_sample([f"stim_{trial_num}_{trial['shape']}_{trial['color']}_{is_target_str}"])
    
    # Record response
    response = False
    rt = None
    
    trial_clock = core.Clock()
    keys = event.getKeys(timeStamped=trial_clock)
    
    # Present stimulus for 200ms
    core.wait(0.200)
    win.flip()  # Clear screen
    outlet.push_sample([f"stim_offset_{trial_num}"])
    
    # Check for responses (allowing for response after stimulus disappears)
    timeout = 0.5  # Allow responses for up to 500ms after stimulus offset
    while trial_clock.getTime() < timeout:
        these_keys = event.getKeys(timeStamped=trial_clock)
        if these_keys:
            keys.extend(these_keys)
            if 'escape' in [k[0] for k in keys]:
                outlet.push_sample(["experiment_aborted"])
                data_file.close()
                win.close()
                core.quit()
                
    # Process key responses
    if keys:
        if 'space' in [k[0] for k in keys]:
            response = True
            # Find the first space key press
            for k in keys:
                if k[0] == 'space':
                    rt = k[1]
                    outlet.push_sample([f"response_{trial_num}_{rt}"])
                    break
    
    # Determine if response was correct
    correct = (trial['is_target'] and response) or (not trial['is_target'] and not response)
    
    # Save data
    data_file.write(f"{trial_num},{trial['shape']},{trial['color']},{trial['is_target']},{trial['isi']},{response},{rt},{correct}\n")
    
    # Check for quit
    if event.getKeys(['escape']):
        outlet.push_sample(["experiment_aborted"])
        break
 
# Mark experiment completion
outlet.push_sample(["experiment_complete"])

# Close everything
data_file.close()
win.close()
 
# Final message
final_win = visual.Window(
    size=(1920, 1080),
    fullscr=False,
    monitor="testMonitor",
    units="norm",
    color=[0, 0, 0]
)
final_message = visual.TextStim(
    final_win,
    text="Experiment complete!\n\nThank you for participating.",
    height=0.1
)
final_message.draw()
final_win.flip()
outlet.push_sample(["final_message_displayed"])
core.wait(3)
final_win.close()

# Clean up LSL outlet before quitting
del outlet
core.quit()