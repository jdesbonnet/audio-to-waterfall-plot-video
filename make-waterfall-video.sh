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



VERSION_NUMBER="0.3.0"
VERSION_DATE="13 Feb 2014"

#
# Script to generate a scrolling spectrum waterfall plot from a MP3 audio file.
# Author: Joe Desbonnet, jdesbonnet@gmail.com
# Version 0.3, 13 Feb 2014.
#
# Dependencies:
# * SoX audio tool
# * GNU Parallel (optional)
# * mp3info
# * ffmpeg
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
#
# See this blog post for more information: 
# http://jdesbonnet.blogspot.ie/2014/02/convert-mp3-to-scrolling-spectrum.html
#
# RELEASE NOTES:
# Version 0.1, 7 Feb 2014:
# First release. Some parameters hard coded and required script edit to change.
#
# Version 0.2 11 Feb 2014:
# Make all important parameters configurable from the command line with switches
# such as -t <title> -r <frame-per-second> etc. Display help if no parameters
# given: full documenation in usage function.
#
# Version 0.3 13 Feb 2014:
# Eliminate need for mencoder. Encode once using ffmpeg. Tested with v2.1.3.
# Option to change output video file name with -o. Defaults to output.mp4



# Display help text
function usage() {
cat <<EOF
./make-waterfall-video.sh options... <mp3file>

Options:

 -c <credit> : will be displayed at bottom left (default credit to this script)
 -t <title> : will be displayed centered on top (default none)
 -d <seconds> : width of the spectrogram in seconds. Determines scroll speed. (default 1)
 -r <frames-per-second> : Video frame rate (default 30)
 -o <output-file> : name of output mp4 file (default output.mp4)
 -h : display this message and exit
 -v : display version and exit

For more information see this blog post:
http://jdesbonnet.blogspot.ie/2014/02/convert-mp3-to-scrolling-spectrum.html

Or GitHub at https://github.com/jdesbonnet/audio-to-waterfall-plot-video
EOF
}

if [ $# -lt 1 ]; then
	usage 
	exit
fi




# Location of tools
MP3INFO=mp3info
SOX=sox
PARALLEL=/home/joe/Downloads/parallel-20140122/src/parallel 
FFMPEG=/var/tmp/ffmpeg-2.1.3/ffmpeg
MENCODER=mencoder

#
# Default value of parameters
#

# Title appears on top-center
TITLE=""

# Credit on bottom-left
CREDIT="https://github.com/jdesbonnet/audio-to-waterfall-plot-video"

# Frame rate of video (frames/second). 24, 30 common choices.
FPS=30

# Width of the spectrogram in seconds. The smaller this value the faster
# the scrolling speed. 1s - 5s are good values.
SPECTROGRAM_WIDTH=1

# Output video file name
OUTPUT_FILE="output.mp4"

# Found that audio was about 0.5s ahead (ie the current
# audio hadn't scrolled into view on the right yet).
# This corrects for it. Why it's needed, not sure.
# Update: after transcoding to H.264 in mp4 this does
# not seem necessary any more.
TWIDDLE=0.0


#
# Parse command line options
#
max=0 
while getopts "c:d:ho:r:t:v" flag ; do
	case $flag in
		c)
		CREDIT=$OPTARG
		;;


		d)
		SPECTROGRAM_WIDTH=$OPTARG
		;;

		r)
		FPS=$OPTARG
		;;

		t)
		TITLE=$OPTARG
		;;

		o)
		OUTPUT_FILE=$OPTARG
		;;

		h)
		usage
		exit
		;;

		v)
		echo "$VERSION_NUMBER $VERSION_DATE"
		exit
		;;

	esac 

	if [ $OPTIND -gt $max ] ; then
		max=$OPTIND 
	fi 
done 

# Shift params to the left so that first param after options is at $1
shift $((max-1))

# Audio file
MP3_FILE=$1

echo "TITLE=${TITLE}"
echo "CREDIT=${CREDIT}"
echo "MP3_FILE=${MP3_FILE}"
echo "SPECTROGRAM_WIDTH=${SPECTROGRAM_WIDTH} seconds"
echo "FPS=${FPS} frames/second"
echo "OUTPUT_FILE=$OUTPUT_FILE"

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
echo "Estimated temporary disk space: $(($nframes*185/1000)) MBytes"

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

# Run lines in PARALLEL_JOB file in parallel which will yield a huge 
# performance boost on a multiprocessor computer. If parallel is not 
# available you could run this as a sequential script file by 
# uncommenting the next line and commenting/removing the line after that.
# . $PARALLEL_JOB
cat $PARALLEL_JOB | $PARALLEL




# Make video MP4 file of spectrogram images.
# This works for FFMPEG 2.1.3. Does not for older FFMPEG 1.0.
# H.264 codec is optional (due to patent concerns) in FFMPEG
# so you may have to build your own version (as I did).
# The default spectrogram image size does not correspond to
# any common video resolution so using -vf scale=1280x720 
# to generate video to the common 720p video resolution.
$FFMPEG -r $FPS -f image2 -pattern_type glob \
 -i 'spectrum-*.png' \
 -i ${MP3_FILE} \
 -vf scale=1280x720 -pix_fmt yuvj420p -c:v libx264 \
 -c:a aac -strict experimental -b:a 192k \
 $OUTPUT_FILE


# Cleanup temporary files
#rm spectrogram-*.png
#rm output.avi
#rm ${MONO_FILE}
#rm ${PARALLEL_JOB}

