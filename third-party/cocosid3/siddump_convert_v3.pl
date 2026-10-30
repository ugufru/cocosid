#!/usr/bin/perl -w
#########################################################################################
#
# converts the output of a SIDdump file to MIDIbox SID parameter format
# SIDdump is available from http://covertbitops.c64.org
# Tutorial: http://www.ucapps.de/howto_sid_wavetables_1.html
#
# Author: tk@midibox.org (2005-12-29)
#
# SYNTAX: siddump_convert.pl <dump-file> [-track <n>] [-time <m:ss>] [-frame <frame>] [-framerate <rate>] [-lines n]
#
#########################################################################################

use Getopt::Long;
use v5.10; # RV 06/10/2012: changed 'switch/case' to 'given/when' for compatibility with Perl v5.16 and up
use Digest::MD5 qw(md5 md5_hex md5_base64);

my $song_name = "R-Type";
my $pattern_length = 96;

#########################################################################################
# Global Settings
#########################################################################################
$frame = -1;
$time = 0;
$lines = 0;
$framerate = 50;
$track = 0;
$debug = 0;

#########################################################################################
# Get arguments
#########################################################################################

GetOptions (
   "debug"   => \$debug,
   "track=s" => \$track,
   "time=s"  => \$time,
   "frame=s" => \$frame,
   "lines=s" => \$lines,
   "framerate=s" => \$framerate,
   );

if( scalar(@ARGV) != 1 )
{
   die "SYNTAX:   siddump_convert.pl <dump-file> [-track <n>] [-time <m:ss>] [-frame <frame>] [-framerate <rate>] [-lines n]\n" .
       "EXAMPLE:  siddump_convert.pl dump.txt -track 2 -time 0:55\n" .
       "EXAMPLE2: siddump_convert.pl dump.txt -track 2 -frame 1937\n";
}

$in_file = $ARGV[0];

if( $frame == -1 ) {

  if( !$time ) {
    die "ERROR: please specify the time (-time <m:ss>) or the frame (-frame <frame>) where the conversion should start!\n";
  }

  my @time = split(/:/, $time);
  if( scalar(@time) != 2 ) {
    die "ERROR: wrong time format, expecting m:ss (minutes:seconds)\n";
  }

  my $minutes = $time[0];
  my $seconds = $time[1];
  my $err = "";

  if( $minutes =~ /[^\d]/ ) {
    $err .= "ERROR: expecting decimal number in minutes\n";
  }
  if( $seconds =~ /[^\d]/ ) {
    $err .= "ERROR: expecting decimal number in seconds\n";
  }
  if( length($err) ) {
    die $err;
  }

  $frame = ($minutes * 60 + $seconds) * $framerate;
 # print "Specified time: ${time} --- starting with frame ${frame}\n";

} else {

  my $seconds = $frame / $framerate;
  my $minutes = int($seconds / 60);
  $seconds = int($seconds - $minutes * 60);
  #printf "Starting with frame ${frame} (%d:%02d)\n", $minutes, $seconds;

}

if( $track < 1 || $track > 3 ) {
  die "ERROR: invalid track selected, must be within 1 and 3\n";
}

#########################################################################################
# Parse dump file
#########################################################################################

open(IN, "<${in_file}") || die "ERROR: cannot open '${in_file}' for reading!\n";

printf("; Converting song $song_name with a pattern length of $pattern_length\n");

my $header_found = 0;
my $frame_found = 0;
my $mbsid_header_print = 0;
my $last_note_val = 0;
my $last_gate = 0;
my $last_trans_val = 0;
my $line = 0;
my $start_frame = 0;
my $rv_last_note;
my $c64startfreq = 0;
my $c64_wave = 0;
my $coco_wave = 0;
my $coco_gate = 0;
my $c64currentfreq = 0;
my $coco_attack_counter = 0;
my $coco_release_counter = 0;
my $att = 0;
my $dec = 0;
my $sus = 0;
my $rel = 0;
my $release_volume = 0;
my $last_cocofreq = 0;

my $current_frame;
my $compress_reference = -1;
my $compress_count = 0;
my $compress_mode = 0;
my $compress_pattern_count_check = 0;
my $compress_pattern_bytes = 0;
my $compressed_total = 0;
my $uncompressed_total = 0;
my @pattern_datas = ();
my $pattern_str = "";
my @pattern_md5s = ();
my $pattern_unique_count = 0;
my $pattern_total_count = 0;
my @pattern_song_sequence = ();

sub dump_song();

warn("Converting track $track...\n");

while( <IN> )
{
  ++$line;

  if( /^\| Frame \| Freq Note\/Abs WF ADSR Pul \| Freq Note\/Abs WF ADSR Pul \| Freq Note\/Abs WF ADSR Pul/ ) {
    $header_found = 1;
  } else {
    @line = split(/\s*\|\s*/, $_);

    if( $header_found && scalar(@line) > 4 ) {
      $current_frame = $line[1];
      my $track_info = $line[1 + $track];

      if( $current_frame >= $frame && ($lines == 0 || ($current_frame < ($frame + $lines))) ) {
	if( !$mbsid_header_print ) {
	  $mbsid_header_print = 1;
	  #print "| Frame | Patrn | Freq Note/Abs WF ADSR Pul | MBSID Wave Transpose   Att Dec Sus Rel |\n";
	  #print "+-------+-------+---------------------------+----------------------------------------+\n";
	}
	$frame_found = 1;
	my $pattern;
	my $freq;
	my $note_val;
	my $wf;
	my $adsr;
	if( $track_info =~ /^(....)\s+[\(]*...\s+(..)[\)]*\s+(..)\s+(....)/ ) {
	  $freq = $1;
	  $note_val = $2;
	  $wf = $3;
	  $adsr = $4;
	  $last_note_val = $note_val;
        } elsif( $track_info =~ /^(....)\s+[\(]*[+-]+\s....[\)]*\s+(..)\s+(....)/ ) {
	  $freq = $1;
	  $note_val = $last_note_val;
	  $wf = $2;
	  $adsr = $3;
	} else {
	  die "ERROR: unknown format in line ${line}:\n$_\n";
        }

	my $seconds = $current_frame / $framerate;
	my $minutes = int($seconds / 60);
	$seconds = int($seconds - $minutes * 60);
	$pattern = "     ";

	if(($current_frame) % $pattern_length == 0)
	{
		$pattern = "-XXX-";
	}

	my $wave = "+00";
	my $gate = 0;
	if( $wf ne ".." ) {
	  $gate = hex($wf) & 1;
	  $wave = sprintf(" %02X", ((hex($wf) & 0xf0) >> 4) | ((hex($wf) & 0x06) << 4) | ($gate ? 0x00 : 0x10));
	}
	
	my $trans = "+000";
	my $trans_rel = "+000";
	if( $note_val ne ".." ) {
		# -16 added by Rem to give proper MIDI note translation
          my $trans_val = 0x40 + (hex($note_val) - 0xa4 - 16);
	  $trans = sprintf(" %03i", $trans_val);

	  if( $adsr ne "...." || (!$last_gate && $gate) ) {
	    $trans_rel = $trans;
	    $last_trans_val = $trans_val;	# RV moved line here.
	  } else {
	    $trans_rel_val = $trans_val - $last_trans_val;
	    if( $trans_rel_val >= 0 ) {
	      $trans_rel = sprintf("+%03i", $trans_rel_val);
	    } else {
	      $trans_rel = sprintf("-%03i", -$trans_rel_val);
	    }
	  }
	  #$last_trans_val = $trans_val;  # RV: Moved line to have note translation always relative to first note
	}

	my $duration = "..";
	if( $adsr ne "...." ) {
	  $att = hex(substr($adsr, 0, 1));
	  $dec = hex(substr($adsr, 1, 1));
	  $sus = hex(substr($adsr, 2, 1));
	  $rel = hex(substr($adsr, 3, 1));
	  
	  # RV: detect when a note is finishing to calculate its duration
	  if($adsr ne "0000")
	  {
	  	$start_frame = $current_frame;
	  	if($note_val ne "..")
	  	{
          my $trans_val = 0x40 + (hex($note_val) - 0xa4 - 16);
	    	$rv_last_note = sprintf("%i", $trans_val);
			#my $hertz = 440 * 2 ** (($trans_val-69)/12.0);
			#my $cocofreq = int($hertz / 76 * 256 + 0.5);
			$c64startfreq = hex($freq);
	    	#$duration = sprintf("Note start ---------");
	    }
	  }
	  else
	  {
	  	#$duration = sprintf("fcb	03,$rv_last_note,%d,1", ($current_frame - $start_frame) / 3);
	  }
	}
	else	# if adsr is "...."
	{
		#if($freq ne "....")
		#{
		#	my $c64currentfreq = hex($freq);
		#	my $c64glide = $c64currentfreq - $c64startfreq;
		#	my $cocoglide = $c64glide / 5.0532;
		#	# this magic ratio constant comes from
		#	# c64 high frequency note AF58 (44888) being equivalent of note (8883) in Coco
		#	$duration = sprintf("%d", $cocoglide);
		#}
	}
	
	# if waveform info is not "..", fetch new information
	if($wf ne "..")
	{
		$c64_wave = hex($wf) & 0xf0;
		$coco_gate = $gate;
		#$coco_gate = 1;	# hack: gate is not handled properly; ignored it for now.
		
		if($c64_wave == 00) # sin wave
		{
			$coco_wave = 1;
		}
		elsif($c64_wave == 0x10) # triangle wave
		{
			$coco_wave = 3;
		}
		elsif($c64_wave == 0x20) # sawtooth wave
		{
			$coco_wave = 2;
		}
		elsif($c64_wave == 0x40) # square / pulse wave
		{
			if($track == 1)	# special case: track 1 uses normal 'square' wave
			{
				$coco_wave = 4;
			}
			else			# ..and track 2 & 3 use inverted modulated 'rect' wave
			{
				$coco_wave = 13;
			}
		}
		elsif($c64_wave == 0x80) # noise wave
		{
			$coco_wave = 16;
		}
		else
		{
			$coco_wave = 2;	 # default to sawtooth when unknown or mixed-up SID waveform
			die "hello";
		}
	}
	# if freq is not "....", fetch new frequency
	if($freq ne "....")
	{
		$c64currentfreq = hex($freq);
	}
	my $coco_result = $coco_wave;
	my $coco_sustain = int($sus * 100 / 15 + 0.5);
	
	# check enveloppe:
	# gate goes from 0 to 1: this is the start of a new note: begin Attack/Decay/sustain processing
	if($last_gate == 0 && $coco_gate == 1)
	{
		$coco_attack_counter = 0;
		$coco_release_counter = 0;
		
		$release_volume = 100;	# start volume at 100, no attack for now
	}
	# gate is still 1: note currently playing, attack/decay/sustain..
	if($last_gate == 1 && $coco_gate == 1)
	{
		$coco_attack_counter++;
		if($coco_wave == 16)	 # special case for noise waveform: increment waveform portion over time
		{
			$coco_result = $coco_wave + ($coco_attack_counter % 5); # loop around portion 16..20
		}
		my $release_speed;	# handle 'decay' similar to release
		given($dec) {
			when(0) { $release_speed = int(6/1000*50 + 0.5); }
			when(1) { $release_speed = int(24/1000*50 + 0.5); }
			when(2) { $release_speed = int(48/1000*50 + 0.5); }
			when(3) { $release_speed = int(72/1000*50 + 0.5); }
			when(4) { $release_speed = int(114/1000*50 + 0.5); }
			when(5) { $release_speed = int(168/1000*50 + 0.5); }
			when(6) { $release_speed = int(204/1000*50 + 0.5); }
			when(7) { $release_speed = int(240/1000*50 + 0.5); }
			when(8) { $release_speed = int(300/1000*50 + 0.5); }
			when(9) { $release_speed = int(750/1000*50 + 0.5); }
			when(10) { $release_speed = int(1.5*50); }
			when(11) { $release_speed = int(2.4*50); }
			when(12) { $release_speed = int(3*50); }
			when(13) { $release_speed = int(9*50); }
			when(14) { $release_speed = int(15*50); }
			when(15) { $release_speed = int(24*50); }
		}
		# calculate volume in 0..100
		if($release_speed == 0)	# instant decay: set directly to 'sustain' volume
		{
			$release_volume = $coco_sustain;
		}
		else
		{
			$release_volume = 100-int((($coco_attack_counter / $release_speed)) * (100-$coco_sustain));
		}
	}
	# gate goes from 1 to 0: note is released: process 'release' portion and fade volume
	if($last_gate == 1 && $coco_gate == 0)
	{
		$coco_release_counter = 0;
	}
	# gate is still 0: keep processing 'release' portion indefinitely until a new note occurs
	if($last_gate == 0 && $coco_gate == 0)
	{
		# compute release speed (in PAL frame number) according to REL (0..15)
		my $release_speed;
		given($rel) {
			when(0) { $release_speed = int(6/1000*50 + 0.5); }
			when(1) { $release_speed = int(24/1000*50 + 0.5); }
			when(2) { $release_speed = int(48/1000*50 + 0.5); }
			when(3) { $release_speed = int(72/1000*50 + 0.5); }
			when(4) { $release_speed = int(114/1000*50 + 0.5); }
			when(5) { $release_speed = int(168/1000*50 + 0.5); }
			when(6) { $release_speed = int(204/1000*50 + 0.5); }
			when(7) { $release_speed = int(240/1000*50 + 0.5); }
			when(8) { $release_speed = int(300/1000*50 + 0.5); }
			when(9) { $release_speed = int(750/1000*50 + 0.5); }
			when(10) { $release_speed = int(1.5*50); }
			when(11) { $release_speed = int(2.4*50); }
			when(12) { $release_speed = int(3*50); }
			when(13) { $release_speed = int(9*50); }
			when(14) { $release_speed = int(15*50); }
			when(15) { $release_speed = int(24*50); }
		}
		$coco_release_counter++;
		# calculate volume in 0..100
		if($release_speed == 0)
		{
			$release_volume = 0;
		}
		else
		{
			$release_volume = int((1-($coco_release_counter / $release_speed)) * $coco_sustain);
		}
	}
	if($release_volume < 0) { $release_volume = 0; }
	if($release_volume > 100) { $release_volume = 100; }

	# evaluate final volume: 0..3:   0=mute, 1=25%   2=50%    3=100%
	my $final_volume = 0;
	if($release_volume > 70) { $final_volume = 3; }
	elsif($release_volume > 35) { $final_volume = 2; }
	elsif($release_volume > 14) { $final_volume = 1; }

	if($final_volume == 2)	# set volume to 50%
	{
		given($coco_wave) {
			when(1) { $coco_result = 5; }
			when(2) { $coco_result = 6; }
			when(3) { $coco_result = 7; }
			when(4) { $coco_result = 8; }
			when(13) { $coco_result = 14; }
			when(16) { $coco_result = 22; }
		}
	}
	elsif($final_volume == 1)  # set volume to 25%
	{
		given($coco_wave) {
			when(1) { $coco_result = 9; }
			when(2) { $coco_result = 10; }
			when(3) { $coco_result = 11; }
			when(4) { $coco_result = 12; }
			when(13) { $coco_result = 15; }
			when(16) { $coco_result = 23; }
		}
	}
	elsif($final_volume == 0) # set volume to mute
	{
		$coco_result = 0;
	}
	
	#$duration = sprintf("freq=$c64currentfreq, waveform=$c64_wave  gate=$coco_gate");
	# see cocosid2.asm for detailed explanation of this frequency conversion:
	my $cocofreq = int($c64currentfreq / 6.1174);
	if($coco_wave == 16)	# special case: lower the freq of noise waveform
	{
		$cocofreq = int($cocofreq/6);
	}
	$duration = sprintf("cocofreq=$cocofreq, waveform=$coco_result volume=$release_volume $coco_attack_counter $coco_release_counter");

	#debug date print:
    #printf("|%6d | %s | %s |        %s %s (%s) %03d %03d %03d %03d | %s\n", $current_frame, $pattern, $track_info, $wave, $trans_rel, $trans, $att, $dec, $sus, $rel, $duration);
    
    # optimisation to help compression:
    # if wave is muted (=0), then ignore frequency and set it to 0 to increase compression ratio
    # same thing if freq is 0: nothing to output
    if($coco_result == 0) { $cocofreq = 0; }
	if($cocofreq == 0) { $coco_result = 0; }
     
    # cocosid data dump:
    if($cocofreq > 8189)
    {
    	warn "  (warning: track $track, frame $current_frame: frequency $cocofreq too high clamped!)\n";
    	if($cocofreq > 8600)
    	{
    		$cocofreq = $cocofreq>>1;	# divide to lower octave since the value it much too high
    	}
    	else
    	{
    		$cocofreq = 8189;	# value is 'just too high' so clamp it but it will sound false..
    	}
    }
    # 16-bit number composed of:
    # 11-bit used for freq (8190 = 13-bit so we need to shift out 2 bits)
    # 5-bit used for waveform
    my $cocofreq_bin = (($cocofreq+2) >> 2);
    my $cocowave_bin = $coco_result << 11;
    
    $coco_output = $cocofreq_bin | $cocowave_bin;
    if(($current_frame) % $pattern_length == 0)
    {
    	begin_new_pattern();
    	
    	#printf("\n\t; frame $current_frame\npattern_t%d_%02d\n", $track,$current_frame/$pattern_length);
	}
	#normal, uncompressed output
    #printf("\tfdb	$coco_output\t; hex=%04X freq=$cocofreq  wave=$coco_result\n", $coco_output);
    #rle_compressor();
    push @pattern_datas,$coco_output;
    $pattern_str .= sprintf("%04X",$coco_output);

	$last_gate = $coco_gate;
    $last_cocofreq = $cocofreq;
      }
    }
  }
}

begin_new_pattern();
printf("; End: Total number of unique patterns:$pattern_unique_count  Total bytes required for this track $track: uncompressed=$uncompressed_total  compressed_total=$compressed_total\n");

dump_song();

if( !$header_found ) {
  die "ERROR: header not found - is this really the output file of SIDdump V1.0?\n";
}

if( !$frame_found ) {
  die "ERROR: frame ${frame} not found - maybe you need to generate a longer file with 'siddump /T600 > dump' (example for 600 seconds)\n";
}

sub begin_new_pattern {
	# special case for first frame: no 'compress stop' to perform
	if($current_frame != 0)
	{
		end_of_pattern();
	}
	@pattern_datas = ();
	$pattern_str = "";
}

sub end_of_pattern()
{
	# Before dumping a pattern on screen, we verify if this pattern as already been seen
	# If so, this is a 'repeating' pattern so no need to process it
	my $md5 = md5_hex($pattern_str);
	my $found = 0;
	
	my $this_pattern_sequence = $pattern_total_count;
	
	# Hack for Battle Valley: 
	#if($track == 1)
	#{
	#	if($this_pattern_sequence == 2 || $this_pattern_sequence == 6) { $md5 = $pattern_md5s[0]; }
	#	if($this_pattern_sequence == 3 || $this_pattern_sequence == 7) { $md5 = $pattern_md5s[1]; }
	#}
	
	for (my $i = 0; $i < @pattern_md5s; $i++)
	{
		if($md5 eq $pattern_md5s[$i])
		{
			warn("pattern $this_pattern_sequence..md5 match\n");
			printf("; pattern %d is a repeat of pattern $i\n", $this_pattern_sequence);
			$this_pattern_sequence = $i;	# substitute pattern with the previously found repeated pattern
			$found = 1;
			last;
		}
	}
	
	push @pattern_md5s,$md5;
	
	if(!$found)
	{
		warn("pattern $this_pattern_sequence..storing new pattern\n");
		compress_pattern();
		#dump_pattern();
		$pattern_unique_count++;
		$uncompressed_total += $pattern_length<<1;
	}
	push @pattern_song_sequence,$this_pattern_sequence;
	
	$pattern_total_count++;

	#die "stoping here.\n";
}

sub compress_pattern()
{
	#printf("; Pattern stored in array: @pattern_datas\n");
	#printf("; There is %i elements\n", scalar(@pattern_datas));
	#printf("; String is: $pattern_str\n");

	# check for batch repetition
	my $mark_string = "----------------------------------------------------------------";
	my $max_batch_len = 8;
	my $nb_batch_this_len = 0; # number of batch of the same length previously processed
	my $tmp_str = $pattern_str;
	my @result_compress = (); # result array of compressed run position
	my @result_nb_batchs = ();
	
	my $batch_len = $max_batch_len;	# length of batch
NEXT_BATCH:	while($batch_len >= 1)
	{
		my $batch_pos = 0;	# start position of first batch
		my %batchs = ();
		my $best_repeat_count = -1;
		my $best_batch_pos = 0;
		my @best_batch_found_array = ();

	LOOP: while($batch_pos <= $pattern_length-$batch_len-$batch_len)
		{
			my @batch_found_array = ();
			my $search_pos = $batch_pos+$batch_len;	# current start position of search
			# note: each data take 4 hex character so we need to shift <<2
			my $current_batch = substr($tmp_str,$batch_pos<<2,$batch_len<<2);
			
			# check if current_batch contains any marked '-' character
			# if so, skip it since part of this batch is already been used by a previous longer batch
			if(index($current_batch,"-") != -1)
			{
				next LOOP;
			}

			# check if this batch has previously been checked (i.e.: if already present in hash)
			if(exists $batchs{ $current_batch })
			{
				$batch_pos++;	# start of next batch to check
				next LOOP;
			}

			my $repeat_count = 0;
			#printf("Current batch pos=$batch_pos, len=$batch_len, batch=[$current_batch]..");
			for (my $i = $search_pos; $i < $pattern_length-$batch_len; ) {
				my $batch = substr($tmp_str,$i<<2,$batch_len<<2);
				# if we found a match, count it
				if($batch eq $current_batch)
				{
					$repeat_count++;
					#printf("batch match found at $i, count is $repeat_count\n");
					push @batch_found_array, $i;
					$i += $batch_len;
				}
				else
				{
					$i++;
				}
			}
			#printf("done: repeat count=$repeat_count\n");
			# done for this batch
			# store it in array for future reference
			$batchs{ $current_batch } = $repeat_count;
			if($repeat_count > $best_repeat_count)
			{
				$best_repeat_count = $repeat_count;
				$best_batch_pos = $batch_pos;
				@best_batch_found_array = @batch_found_array;
			}
		}
		continue
		{
			$batch_pos++;	# start of next batch to check
		}
		
		# calculate compressed space gained:
		# each data takes 2 byte, but subtract 1 from batch_len to account for the 'compressed data byte' itself
		# and a final -1 byte because even if we found 0 batch, the selected batch will cost 1 byte
		my $compression_gain = $best_repeat_count*($batch_len*2 - 1) - 1;
		# if this batch gives no compression gain, we are done: proceed with shorter length
		if($compression_gain > 0)
		{
			my $best_batch = substr($tmp_str,$best_batch_pos<<2,$batch_len<<2);
			#printf(";  batch length=$batch_len, best repeat count is $best_repeat_count for batch pos $best_batch_pos [$best_batch]\n");
			# add the reference batch itself so it will be marked too
			push @best_batch_found_array, $best_batch_pos;
			# now mark batch as 'used' so there are not referenced by remaining batch length
			push @result_compress, $best_repeat_count+1;	# store in result array the number of repeat+1 for this run
			foreach(@best_batch_found_array)
			{
				substr($tmp_str,$_<<2,$batch_len<<2) = substr($mark_string,0,$batch_len<<2);
				push @result_compress, $_;	# then store list of position for compressing repeat of this run
			}
			

			#printf("; Compression gain for this batch: $compression_gain\n");
			$nb_batch_this_len++;
			#printf("; Resul str: $tmp_str\n");
			if($nb_batch_this_len == 8)
			{
				warn("  Reached maximum of 8 batch of same size\n");
				$compression_gain = 0; # force switching to next batch size
			}
		}
		
		if($compression_gain <= 0)
		{
			#printf("; Done for batch length=$batch_len, total batch of this length=$nb_batch_this_len, proceed to shorter batch length\n");
			push @result_nb_batchs, $nb_batch_this_len;	# store in array how many batch of this length were processed
			$nb_batch_this_len = 0;
			$batch_len--;	# proceed with next shorter batch length
		}		
    }

	my $count_byte = 0;
    printf("pattern_t%d_%02d\n", $track,$pattern_total_count);
	printf("; start of compressed data information header\n");
	# Compression is complete. Now emit compressed pattern result
	# first part: calculate how many bytes of compressed-batch are present before actual data stream
	my $count_batch = 0;
	for (my $i = 0; $i < $max_batch_len; $i++)
	{
		my $batch_nb = $result_nb_batchs[$i];
		if($batch_nb > 0)
		{
			$count_batch++;
		}
	}
	printf("\tfcb\t$count_batch\t; There are $count_batch batch stored in header:\n");
	$count_byte++;
	my $offset = 1;	# word offset to where a batch begins
	my $rescomp = 0;
	for (my $i = 0; $i < $max_batch_len; $i++)
	{
		my $batch_nb = $result_nb_batchs[$i];
		if($batch_nb > 0)
		{
			my $batch_len = $max_batch_len-$i;
			my $output = ($batch_nb<<3) + $batch_len-1;
			printf("\tfcb\t$output\t; (batch_nb<<3)+batch_len-1:  we have $batch_nb batch of length: $batch_len\n");
			$count_byte++;
			
			for(my $k=0; $k < $batch_nb; $k++)
			{
				my $nb_run = $result_compress[$rescomp++];
				#printf("batch $k, there is $nb_run runs\n");
				for($j = 0; $j < $nb_run; $j++)
				{
					my $pos = $result_compress[$rescomp++];
					if($j == 0)
					{
						my $current_batch = substr($pattern_str,$pos<<2,$batch_len<<2);
						printf("\tfdb\t");
						for(my $i2=0; $i2<$batch_len; $i2++)
						{
							printf("\$%s",substr($pattern_str,($pos+$i2)<<2,1<<2));
							if($i2 < $batch_len-1) { printf(","); }
						}
						printf("\t  ; offset: $offset batch#=$k  batch=[$current_batch]\n");
						$offset += $batch_len;
						$count_byte += $batch_len<<1;
					}
				}
			}			
		}
	}
	
	printf("; start of data stream\n");
EMIT_STREAM:	for (my $i3 = 0; $i3 < $pattern_length;)
	{
		my $current = substr($tmp_str,$i3<<2,1<<2);
		# if current word is compressed, find in which batch group
		if($current eq "----")
		{
			my $rescomp = 0;
			for (my $i = 0; $i < $max_batch_len; $i++)
			{
				my $batch_nb = $result_nb_batchs[$i];
				my $batch_len = $max_batch_len-$i;
				for(my $k=0; $k < $batch_nb; $k++)
				{
					my $nb_run = $result_compress[$rescomp++];
					for($j = 0; $j < $nb_run; $j++)
					{
						my $pos = $result_compress[$rescomp++];
						if($pos == $i3) # bingo, we have found the group
						{
							my $current_batch = substr($pattern_str,$pos<<2,$batch_len<<2);
							my $result = ((24+$batch_len-1)<<3) + ($k);
							printf("\tfcb\t$result\t	; compressed, batch_len=$batch_len, batch no=$k, pos=$i3 batch=[$current_batch]\n");
							$i3 += $batch_len;
							$count_byte++;
							next EMIT_STREAM;
						}
					}
				}
			}
			
		}
		else
		{
			printf("\tfdb\t\$$current	; uncompressed, pos=$i3\n");
			$count_byte+=2;
			$i3++;
		}
	}
	
	printf("; Real compressed output bytes: $count_byte (so gain is: %i bytes)\n", ($pattern_length<<1)-$count_byte);
	$compressed_total += $count_byte;
	#die("Stopping here.");
}

sub dump_pattern() {
    printf("pattern_t%d_%02d\n", $track,$pattern_total_count);
	for (my $i = 0; $i < @pattern_datas; $i++) {
		if($i % 16 == 0) { printf("\n\tfdb	"); }
    	printf("\$%04X", $pattern_datas[$i]);
		if($i % 16 < 15) { printf(","); }    	
    }
    printf("\n\n");
}

sub dump_song()
{
	printf("\n; pattern list for this track $track, total length of song is $pattern_total_count pattern:\n");
	printf("song_voice$track\n");
	for (my $i = 0; $i < $pattern_total_count; $i++)
	{
		printf("\tfdb\tpattern_t%d_%02d\n", $track,$pattern_song_sequence[$i]);
	}
	printf("\tfdb\t\$ffff\t; enable this line if you want to reset/restart song indefinitely\n");
	printf("\tfdb\t00\t; or this line to stop\n");
}
