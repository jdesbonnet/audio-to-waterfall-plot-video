#!/bin/bash

#
# Script to test make-waterfall-video.sh
#

rm -f -r test_job
mkdir test_job
cd test_job

# Make a test tone, 15s duration with tone at 262Hz and 1000Hz.
sox -n test.mp3 synth 15 sin 262 sin 1000

# Generate waterfall plot video
bash ../make-waterfall-video.sh test.mp3

