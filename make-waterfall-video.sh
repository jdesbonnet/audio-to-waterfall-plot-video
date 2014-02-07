#!/bin/bash

# Copyright (c) 2014, Joe Desbonnet
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the <organization> nor the
#      names of its contributors may be used to endorse or promote products
#      derived from this software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.



#
# Script to generate a scrolling spectrum waterfall plot from a MP3 audio file.
# Joe Desbonnet, jdesbonnet@gmail.com
# Version 0.1, 7 Feb 2014.
#
# There are a few problems with this script:
# You'll need to edit to change title/credit on plot. TODO move to command line
# I've used mencoder to assemble the PNG files into a video, but I find the 
# a/v sync is off. However if converted to H.264 mp4 with ffmpeg it's fine.
# Ideally I'd like to create the video with just ffmpeg, but for some reason
# the version of ffmpeg I have is not working in PNG->video mode.
# Also the version of GNU Parallel in the Ubuntu (13.04) repo doesn't work:
# need to download latest version and update the PARALLEL config below.
# The current implementation is very resource intensive. In particular you
# need *lots* of temporary disk space. This can be improved by generating
# the video in fragments and deleting the PNG files after a fragment is 
# generated.

TITLE="Toccata and Fugue in D Minor (Music credit: archive.org, public domain)"
#TITLE="Morning concert, Lausanne Cathedral, 2014-02-01"
CREDIT="Rendering by Joe Desbonnet  http://jdesbonnet.blogspot.ie"

# Location of tools
MP3INFO=mp3info
SOX=sox
PARALLEL=/home/joe/Downloads/parallel-20140122/src/parallel 
FFMPEG=/var/tmp/ffmpeg-1.0/ffmpeg
MENCODER=mencoder

# Frame rate of video. 24, 30 common choices.
FPS=30

# Width of the spectrogram in seconds
SPECTROGRAM_WIDTH=1

# Found that audio was about 0.5s ahead (ie the current
# audio hadn't scrolled into view on the right yet).
# This corrects for it. Why it's needed, not sure.
# Update: after transcoding to H.264 in mp4 this does
# not seem necessary any more.
TWIDDLE=0.0

# Audio file
MP3_FILE=$1

# Parallel job file
PARALLEL_JOB="_parallel_jobs.sh"
MONO_FILE="_mono.wav"

# Get length of MP3 file audio in seconds
audio_length=`${MP3INFO} -p "%S" ${MP3_FILE}`

# Make mono WAV of MP3 and down sample to 8k. We use this
# for the spectrogram. If we use the original high quality
# audio all the interesting bits will be squashed at the
# very bottom. So use downsampled version for visual, but
# add the original high quality audio to the video at end.
# If you want to see more detail try 4k sampling. For ref
# middle-C is about 262Hz.
${SOX} ${MP3_FILE} -r 8k -o ${MONO_FILE} remix 1,2

# Number of frames (len * FPS)
nframes=`bc -l <<< "$audio_length*$FPS"`

echo "Title (top): $TITLE"
echo "Credit (bottom/left): $CREDIT"
echo "Number of frames to generate: $nframes"
echo "Estimated temporary disk space: $(($nframes*130/1000)) MBytes"

if [ -e $PARALLEL_JOB ]; then
	rm $PARALLEL_JOB
fi

# Want the current audio to appear at the right and then scroll to left.
# So need to wait for width*fps frames before starting animation.
x=$((${SPECTROGRAM_WIDTH}*${FPS}))

# Make parallel job file. Unfortunately very slow due to invocation of bc. 
# bc is used because float math is required. bash only supports int math.
# Add 1000000 to frame number so that file globbing returns files in correct
# order.
for (( i=0; i<=$nframes; i++ )); do
  t=`bc -l <<< "$i/$FPS"`
  if [ $i -lt $x ]; then
	audio_offset=0
  else
    audio_offset=`bc -l <<< "${t}-${SPECTROGRAM_WIDTH}+${TWIDDLE}"`
  fi
  tf=`printf '%0.2f' $t`
  ii=$(($i+1000000))
  echo "sox ${MONO_FILE} -n spectrogram -d 0:${SPECTROGRAM_WIDTH} -S $audio_offset -t \"${TITLE} t=$tf\" -c \"${CREDIT}\" -o spectrum-${ii}.png" >> $PARALLEL_JOB
done

# Run lines in PARALLEL_JOB file in parallel
cat $PARALLEL_JOB | $PARALLEL

# TODO: should be necessary to encode to video only once, but ffmpeg png 
# input is not working for me for some reason.

# Make video AVI file of spectrograms. When I play back with mplayer
# a/v sync is off by ~0.5s. However when converted again with ffmpeg
# to H.264 all is right. So not sure what's going on here.
$MENCODER mf://spectrum-*.png \
-mf fps=${FPS}:type=png \
-ovc lavc -lavcopts vcodec=mpeg4:vbitrate=3200 \
-audiofile ${MP3_FILE} -oac copy  \
-o output.avi 

# Now convert to H.264 MP4. This fixes a/v timing problem.
$FFMPEG -i output.avi -c:v libx264 -c:a libfaac output.mp4

# Cleanup temporary files
#rm spectrogram-*.png
#rm output.avi
#rm ${MONO_FILE}
#rm ${PARALLEL_JOB}

