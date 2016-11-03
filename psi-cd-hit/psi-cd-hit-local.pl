#!/usr/bin/perl -w
################################################################################
######### PSI-cd-hit written by Weizhong Li at http://cd-hit.org
################################################################################
our $pid       = $$;
our $db_in     = "";   ###################
our $db_out    = "";   # input / output
our $len_t     = 10;   ###################
our $NR_clstr  = 0.3;  #
our $NR_clstre = -1;   #thresholds
our $g_iden    = 1;    #
our $opt_aS    = 0.0;  #
our $opt_aL    = 0.0;  #
our $circle    = 0;    #
our $opt_g     = 1;    ####################
our $blast_exe = "blastall -p blastp -m 8";               #########################
our $prof_exe  = "blastpgp -m 8";                         #
our $prof_para = "-j 3 -F T -e 0.001 -b 500 -v 500";      #
our $prof_db   = "";                                      #
our $bl_para   = "-F T -e 0.000001 -b 100000 -v 100000";  #  program
our $bl_STDIN  = 1;                                       #
our $keep_bl   = 0;                                       #
our $blast_prog= "blastp";                                #
our $formatdb  = "formatdb";                              #########################
our $exec_mode = "local";      #######################
our $num_qsub   = 1;            #
our $para_no   = 1;            # compute
our $sh_file   = "";           #
our $batch_no_per_node = 50;   #######################
our $reformat_seg = 50000;
our $restart_seg  = 20000;
our $job          = "";
our $job_file     = "";
our $date         = `date`;
our $restart_in   = "";
our $pwd          = `pwd`; chop($pwd);
our $db_clstr;
our $db_log;
our $db_out1;
our $seq_dir;
our $bl_dir;
our $restart_file;
our $tmp_db;
our $remote_perl_script;
our $remote_sh_script;
our $bl_path;
our $bl_plus = 1;   #### use blast+ 
our $bl_threads = 1;
our $skip_long = 0;

sub parse_para_etc {
  my ($arg, $cmd);
  while($arg = shift) {
    ## input/output:
    if    ($arg eq "-i")          { $db_in     = shift; }
    elsif ($arg eq "-o")          { $db_out    = shift; }
    elsif ($arg eq "-l")          { $len_t     = shift; }
    ## thresholds
    elsif ($arg eq "-c")          { $NR_clstr  = shift; }
    elsif ($arg eq "-ce")         { $NR_clstre = shift; }
    elsif ($arg eq "-G")          { $g_iden    = shift; }
    elsif ($arg eq "-aL")         { $opt_aL    = shift; }
    elsif ($arg eq "-aS")         { $opt_aS    = shift; }
    elsif ($arg eq "-g")          { $opt_g     = shift; }
    elsif ($arg eq "-circle")     { $circle    = shift; }
    elsif ($arg eq "-sl")         { $skip_long = shift; }
    ## program
    elsif ($arg eq "-prog")       { $blast_prog= shift; }
    elsif ($arg eq "-p")          { $prof_para = shift; }
    elsif ($arg eq "-dprof")      { $prof_db   = shift; die "option -dprof no longer supported!";}
    elsif ($arg eq "-s")          { $bl_para   = shift; }
    elsif ($arg eq "-k")          { $keep_bl   = shift; }
    elsif ($arg eq "-bs")         { $bl_STDIN  = shift; }
    ## compute
    elsif ($arg eq "-exec")       { $exec_mode = shift; }
    elsif ($arg eq "-host")       { $num_qsub   = shift; }
    elsif ($arg eq "-para")       { $para_no   = shift; }
    elsif ($arg eq "-shf")        { $sh_file   = shift; }
    elsif ($arg eq "-blp")        { $bl_threads   = shift; }
    ## job:
    elsif ($arg eq "-rs")         { $restart_seg = shift; }
    elsif ($arg eq "-rf")         { $reformat_seg= shift; }
    elsif ($arg eq "-restart")    { $restart_in= shift;   }
    elsif ($arg eq "-J")          { $job       = shift; $job_file = shift; }
    ## blast path
    elsif ($arg eq "-P")          { $bl_path   = shift;   }
    else                          { print_usage(); exit(); }
  }

  # speical jobs
  if ($job eq "parse_blout") { job_parse_blout(); exit();}

  if ($blast_prog eq "blastn") {
    $formatdb  = "formatdb -p F";
    $blast_exe    = "blastall -p blastn -m 8";
  }
  elsif ($blast_prog eq "megablast") {
    $blast_prog = "blastn"; #### back to blastn for blast parser type
    $formatdb  = "formatdb -p F";
    $blast_exe    = "megablast -H 100 -D 2 -m 8";
  }
  elsif ($blast_prog eq "blastpgp") {
    $blast_exe  = "blastpgp -m 8 -j 3";
  }

  #### for blast+
  if ($bl_plus) {
    $formatdb = "makeblastdb -dbtype prot -max_file_sz 8GB";
    $blast_exe = "blastp -outfmt 6";
    $bl_para   = "-seg yes -evalue 0.000001 -num_alignments 100000 -num_threads $bl_threads";  #  program

    if ($blast_prog eq "blastn") {
      $formatdb = "makeblastdb -dbtype nucl -max_file_sz 8GB";
      $blast_exe    = "blastp -task blastn -outfmt 6";
      $bl_para   = "-dust yes -evalue 0.000001 -num_alignments 100000 -num_threads $bl_threads";  #  program
    }
    elsif ($blast_prog eq "megablast") {
      $blast_prog = "blastn"; #### back to blastn for blast parser type
      $formatdb = "makeblastdb -dbtype nucl -max_file_sz 8GB";
      $blast_exe    = "blastp -task megablast -outfmt 6";
      $bl_para   = "-dust yes -evalue 0.000001 -num_alignments 100000 -num_threads $bl_threads";  #  program
    }
    elsif ($blast_prog eq "blastpgp") {
      $blast_exe  = "psiblast -outfmt 6 -num_iterations 3 -num_threads $bl_threads";
    }
  }

  if ($bl_path) {
    $blast_exe = "$bl_path/$blast_exe";
    $formatdb  = "$bl_path/$formatdb";
  }

  (-e $db_in) || die "No input";
  ($db_out)   || die "No output";

  $db_clstr  = "$db_out.clstr";
  $db_log    = "$db_out.log";
  $db_out1   = "$db_out.out";
  $seq_dir   = "$db_in-seq";
  $bl_dir    = "$db_in-bl";
  $restart_file   =" $db_out.restart";

  $tmp_db    = "$db_in.$pid";
  $remote_perl_script = "$tmp_db-bl.pl";
  $remote_sh_script   = "$tmp_db-bl.sh";

  $cmd = `mkdir $bl_dir $seq_dir`;

  write_remote_perl_script();
  write_remote_sh_script();
  return;
}
########## END parse_para_etc


sub read_db {
  my $des = "";
  my $seq = "";
  my $ll;

  open(DBIN, $db_in)         || die "Can not open $db_in";
  while($ll=<DBIN>){
    chop($ll);
    if ($ll =~ /^>/) {
      $seq =~ s/\s//g;
      if (length($seq) > $len_t) { add_seq($des, $seq); }
      $des = $ll; $seq = "";

    }
    else { $seq .= $ll; }
  }
  $seq =~ s/\s//g;
  if (length($seq) > $len_t) { add_seq($des, $seq); }
  close(DBIN);

  ($NR_no >=1 ) || die "No sequence readin";

  print OUTT "Total seqs $NR_no in $db_in\n";
  return;
}
########## END read_db


sub add_seq {
  my ($des, $seq) = @_;
  $des =~ s/\s.+$//;
  push(@seqs,   $seq);
  push(@dess,   $des);
  push(@lens,   length($seq));
  push(@idens,  0);
  push(@passeds,0);
  push(@NR_clstr_nos,0); 
  push(@in_bg, 0);
  $NR_no++; 
  return;
}
########## END add_seq


sub open_LOG {
  open(OUTT, ">> $db_out1") || die "can not open $db_out1";
  select(OUTT); $|++; ### file handle flush
  print OUTT "Started $date";

  open(LOG, ">> $db_log")     || die "Can not open $db_log";
  select(LOG); $|++; ### file handle flush
  select(STDOUT);
  return;
}
########## END open_LOG


{## use static variables
my $last_NR90_no=0;
my $last_NR_passed=0;
sub watch_progress {
  my ($i0, $NR90_no, $NR_passed, $NR_no, $flag) = @_;
  my $i1 = $i0+1;

  if ( $i1 % 10 == 0 ) {
    print OUTT ".";
    $flag = 1 if ( $i1 % 100 == 0 );
  }

  if ($flag) {
    my $t1 = (int($NR_passed/$NR_no*10000)) / 100;
    my $t90 = $NR90_no - $last_NR90_no;
    my $tno = $NR_passed - $last_NR_passed; 
    my ($tu, $ts, $cu, $cs) = times();
    my $tt = $tu + $ts + $cu + $cs;
    print OUTT 
      "$i1 finished $NR90_no clusters $NR_passed passed $t90/$tno clstr/passed $t1% done $tt cpu\n";
    $last_NR90_no = $NR90_no;
    $last_NR_passed = $NR_passed;
  }
  return;
}
}


sub close_LOG {
  my $date = `date`; print OUTT "Completed $date\n";
  my $total_cpu = total_remote_cpu();
  print OUTT "Total CPUs on remote hosts: $total_cpu\n";
  close(OUTT);
  close(LOG);
  return;
}
########## END close_LOG

###### need to change to read dir because 
sub total_remote_cpu {
  my ($i, $j, $k, $ll);
  my $tt = 0;
  for ($j=0; $j<$num_qsub; $j++) {
    open(TCPU, "$seq_dir/host.$j.cpu") || next;
    while($ll = <TCPU>) {
      chop($ll);
      $tt += $ll;
    }
    close(TCPU);
  }
  return $tt;
}
########## END total_remote_cpu


sub job_parse_blout {
  my ($i, $j, $k);
  my @hits = process_blout_blastp_blastn($job_file);

  open(BLOUT2, "> $job_file.out") || return;
  foreach $i (@hits) {
    print BLOUT2 join("\t", @{$i}), "\n";
  }
  print BLOUT2 "#\n";
  close(BLOUT2);
  return;
}
########## END job_parse_blout


sub write_restart {
  my ($i0, $i, $j, $k);
  open(RES, "> $restart_file") || die;

  for ($i0=0; $i0<$NR_no; $i0++) {
    $i = $NR_idx[$i0];
    print RES "$i\t$NR_clstr_nos[$i]\t$idens[$i]\t$passeds[$i]\n";
  }

  close(RES);
  return;
}
########## END write_restart


sub read_restart {
  my ($ii, $i0, $i, $j, $k, $ll);
  my @lls;
  open(RESIN, $restart_in) || die;

  $NR_passed = 0;
  $NR90_no   = 0;
  $ii = -1;
  $i0 = 0;
  while($ll = <RESIN>) {
    chop($ll);
    @lls = split(/\t/,$ll);
    $i = $lls[0];
    $NR_clstr_nos[$i] = $lls[1];
    $idens[$i]       = $lls[2];
    $passeds[$i]     = $lls[3];
    $NR_passed++   if ($lls[3]);

    if ($lls[2] eq "*") { #rep
      $NR90_no++; 
      $ii = $i0 if ($lls[3]);
    }
    $NR_idx[$i0] = $i;
    $i0++; # idx of sorted , see write_restart 
  }
  close(RESIN);

  $ii++; # $ii to be last rep processed
  return $ii;
}
########## END read_restart


sub write_db_clstr {
  my ($i0, $i, $j, $k);

  my @NR90_seq = ();
  for ($i=0; $i<$NR90_no; $i++) { $NR90_seq[$i] = []; }
  for ($i0=0; $i0<$NR_no; $i0++) {
    $i = $NR_idx[$i0];
    next unless ($passeds[$i]);
    $j = $NR_clstr_nos[$i];
    next unless ($j < $NR90_no);
    push(@{$NR90_seq[$j]}, $i);
  }

  open(DBCLS, "> $db_clstr") || die "Can not write $db_clstr";
  for ($i=0; $i<$NR90_no; $i++) {
    print DBCLS ">Cluster $i\n";
    $k = 0;
    foreach $j (@{ $NR90_seq[$i] }) {
      my $des = (split(/\s+/,$dess[$j]))[0];
      print DBCLS "$k\t$lens[$j]"."aa, $des... ";
      if ($idens[$j] eq "*") { print DBCLS "*\n"; }
      else                   { print DBCLS "at $idens[$j]\n";}
      $k++;
    }
  }
  close(DBCLS);

  @NR90_seq=();
  return;
}
########## END write_db_clstr


sub remove_raw_blout {
  my $NR_sofar = shift;
  my ($i0, $i, $j, $k, $cmd);
  return if ($keep_bl);

  for ($i0=$NR_sofar; $i0>=0; $i0--) {
    $i = $NR_idx[$i0];
    next unless $passeds[$i];
    next unless ($idens[$i] eq "*"); #only reps have blout
    my $fout = "$bl_dir/$i";
    last unless (-e "$fout.out");    #removed from last call
    if (not $bl_STDIN) { $cmd = `rm -f $fout`; }
    $cmd = `rm -f $bl_dir/$i.out`;
  }
  return;
}
########## END remove_raw_blout


sub remove_raw_blout_bg {
  my $NR_sofar = shift;
  my ($i0, $i, $j, $k, $cmd);
  return if ($keep_bl);

  my $tmp_sh_script   = "$tmp_db-rm-$NR_sofar.sh";
  open(OUTRM, ">$tmp_sh_script") || die "can not write to $tmp_sh_script";

  for ($i0=$NR_sofar; $i0>=0; $i0--) {
    $i = $NR_idx[$i0];
    next unless $passeds[$i];
    next unless ($idens[$i] eq "*"); #only reps have blout
    my $fout = "$bl_dir/$i";
    last unless (-e "$fout.out");    #removed from last call
    if (not $bl_STDIN) { print OUTRM "rm -f $fout\n"; }
    print OUTRM "rm -f $bl_dir/$i.out";
  }
  print OUTRM "rm -f $tmp_sh_script\n"; ## remove self
  close(OUTRM);
  sleep(3);

  $cmd = `sh $tmp_sh_script >/dev/null 2>&1 &`;
  return;
}
########## END remove_raw_blout_bg


sub fish_other_homolog {
  my ($i, $j, $k, $i0, $j0, $k0);
  $id = shift; # real idx, not sorted idx
  my @hits = ();

  wait_blast_out("$bl_dir/$id.out");
  open(BLPOUT, "$bl_dir/$id.out") || return;
  while($i=<BLPOUT>) {
    last if ($i =~ /^#/);
    chop($i);
    push(@hits, [split(/\t/,$i)]);
  }
  close(BLPOUT);
  my $rep_len = $lens[$id];

  foreach $i (@hits) {
    my $id1 = $i->[0];
    next unless ($id1 < $NR_no); 
    next if ($idens[$id1] eq "*"); #existing reps
    next if ($lens[$id1] > $rep_len); # in opt_g=1 mode, preventing it from being clustered into short rep

    if ( $passeds[$id1] ) { #### if this hit is better -g 1 mode
      my $old_e = (split(/\//,$idens[$id1]))[0];
      if ($i->[3] < $old_e) {
        $idens[$id1]   = "$i->[3]/$i->[2]aa/$i->[1]%";
        $passeds[$id1] = 1;
        $NR_clstr_nos[$id1] = $NR90_no;
      }
      next;
    }

    $idens[$id1]   = "$i->[3]/$i->[2]aa/$i->[1]%";
    $passeds[$id1] = 1;
    $NR_clstr_nos[$id1] = $NR90_no;
    $NR_passed++;
  }
  return;
}
########## END fish_other_homolog


########### if a hit has multiple HSPs on both + - strands
########### keep only the HSPs, whose strand is same as the top HSP
sub keep_strand_with_top_hsp {
  my $self = shift;
  my ($i,$j,$k);

  my %id_2_strand = ();
  my @new_sbj = ();
  my $new_no = 0;
  for ($i=0; $i<$self->{no}; $i++) {
    my $p = $self->{sbj}->[$i];
    my ($id1, $len_sub) = split(/\./, $p->{id});
    if (not defined($id_2_strand{$id1})) {
      $id_2_strand{$id1} = $p->{frame};
    }
    if ($p->{frame} eq $id_2_strand{$id1}) { #### this stand is same as the top strand
      push(@new_sbj, $self->{sbj}->[$i]);
      $new_no++;
    }
  }
  $self->{no} = $new_no;
  $self->{sbj} = [@new_sbj];
}
########## END keep_strand_with_top_hsp

########## for blastpgp -j no (no>1)
########## keep hits from the last round
sub keep_hsp_of_last_round {
  my $self = shift;
  my ($i,$j,$k);

  my @new_sbj = ();
  my $new_no  = 0;
  my $last_score = 9999999*9999999*9999999; # a big one
  for ($i=0; $i<$self->{no}; $i++) {
    my $p = $self->{sbj}->[$i];
    my $score = $p->{score};

    if ($score > $last_score) { ## this is new round of hits
      @new_sbj = ();
      $new_no  = 0;
    }
    $last_score = $score;
    push(@new_sbj, $self->{sbj}->[$i]);
    $new_no++;
  }
  $self->{no} = $new_no;
  $self->{sbj} = [@new_sbj];
}
########## END keep_hsp_of_last_round

########## if a query hit a subject with multiple HSPs
########## only the top HSP is kept
sub keep_top_hsp {
  my $self = shift;
  my ($i,$j,$k);

  my %id_exist = ();
  my @new_sbj = ();
  my $new_no = 0;
  for ($i=0; $i<$self->{no}; $i++) {
    my $p = $self->{sbj}->[$i];
    my ($id1, $len_sub) = split(/\./, $p->{id});
    
    if (not defined($id_exist{$id1})) {
      $id_exist{$id1} = 1;
      push(@new_sbj, $self->{sbj}->[$i]);
      $new_no++;
    } 
  } 
  $self->{no} = $new_no;
  $self->{sbj} = [@new_sbj];
}
########## keep_top_hsp

########## let the top hsp to start at 0 for both query and subject
########## i.e. the begining of HSP to be new original - coordinate 0
########## then reset all other HSPs' alignment coordinates
sub reset_alignment_coor_for_circle_seq {
  my $self = shift;
  my ($i,$j,$k);

  my $last_id = "";
  $j = 0;
  my $hsp_count = 0; # number of HSPs for a subject
  for ($i=0; $i<$self->{no}; $i++) {
    my $p = $self->{sbj}->[$i];
    my ($id1, $len_sub) = split(/\./, $p->{id});

    if ($id1 ne $last_id) {
      if ($hsp_count > 1) {  # it is necessary to reset coordinate when at least 2 HSP
        my $p_top_hsp = $self->{sbj}->[$j];
        my $len_q = (split(/\./, $p_top_hsp->{qid}))[1];
        my $len_s = (split(/\./, $p_top_hsp->{id}))[1];
        my $ref_q = ($p_top_hsp->{qfrom} < $p_top_hsp->{qend}) ? $p_top_hsp->{qfrom} : $p_top_hsp->{qend};
        my $ref_s = ($p_top_hsp->{sfrom} < $p_top_hsp->{send}) ? $p_top_hsp->{sfrom} : $p_top_hsp->{send};
        for ($k = $j; $k<$j+$hsp_count; $k++) {
          $self->{sbj}->[$k]->{qfrom} -= $ref_q; if ($self->{sbj}->[$k]->{qfrom} < 0) {$self->{sbj}->[$k]->{qfrom} += $len_q;}
          $self->{sbj}->[$k]->{qend}  -= $ref_q; if ($self->{sbj}->[$k]->{qend}  < 0) {$self->{sbj}->[$k]->{qend}  += $len_q;}
          $self->{sbj}->[$k]->{sfrom} -= $ref_s; if ($self->{sbj}->[$k]->{sfrom} < 0) {$self->{sbj}->[$k]->{sfrom} += $len_s;}
          $self->{sbj}->[$k]->{send}  -= $ref_s; if ($self->{sbj}->[$k]->{send}  < 0) {$self->{sbj}->[$k]->{send}  += $len_s;}
        }
      }
      $j = $i;
      $hsp_count = 0;
    }
    $last_id = $id1;
    $hsp_count++;
  }

      #last subject
      if ($hsp_count > 1) {  # it is necessary to reset coordinate when at least 2 HSP
        my $p_top_hsp = $self->{sbj}->[$j];
        my $len_q = (split(/\./, $p_top_hsp->{qid}))[1];
        my $len_s = (split(/\./, $p_top_hsp->{id}))[1];
        my $ref_q = ($p_top_hsp->{qfrom} < $p_top_hsp->{qend}) ? $p_top_hsp->{qfrom} : $p_top_hsp->{qend};
        my $ref_s = ($p_top_hsp->{sfrom} < $p_top_hsp->{send}) ? $p_top_hsp->{sfrom} : $p_top_hsp->{send};
        for ($k = $j; $k<$j+$hsp_count; $k++) {
          $self->{sbj}->[$k]->{qfrom} -= $ref_q; if ($self->{sbj}->[$k]->{qfrom} < 0) {$self->{sbj}->[$k]->{qfrom} += $len_q;}
          $self->{sbj}->[$k]->{qend}  -= $ref_q; if ($self->{sbj}->[$k]->{qend}  < 0) {$self->{sbj}->[$k]->{qend}  += $len_q;}
          $self->{sbj}->[$k]->{sfrom} -= $ref_s; if ($self->{sbj}->[$k]->{sfrom} < 0) {$self->{sbj}->[$k]->{sfrom} += $len_s;}
          $self->{sbj}->[$k]->{send}  -= $ref_s; if ($self->{sbj}->[$k]->{send}  < 0) {$self->{sbj}->[$k]->{send}  += $len_s;}
        }
      }

  return;
}
########## reset_alignment_coor_for_circle_seq


sub process_blout_blastp_blastn {
  my ($i, $j, $k, $i0, $j0, $k0);
  my $blout = shift;
  my @blhits = ();

  #### need $len_rep
  my $len_rep = 0;
  my $bl = readblast_m8("", $blout);
  if ($blast_prog eq "blastn") { keep_strand_with_top_hsp($bl); }
  if (($blast_prog eq "blastpgp") and (not $prof_db)) {keep_hsp_of_last_round($bl); }

  if ($g_iden == 0 ) { #### Local identity
    keep_top_hsp($bl); #### local alignment, only the top HSP

    for ($i=0; $i<$bl->{no}; $i++) {
      my $p = $bl->{sbj}->[$i];
      my ($id1, $len_sub) = split(/\./, $p->{id});
      my $frame = $p->{frame};
      if (not $len_rep) {$len_rep = (split(/\./,$p->{qid}))[1]; }
      my $iden       = $p->{iden};
      my $cov_aS     = $p->{alnln} / $len_sub;
      my $cov_aL     = $p->{alnln} / $len_rep;
      my $exp1       = $p->{expect};

      if (($iden/100 > $NR_clstr or $exp1<$NR_clstre) and ($cov_aS >= $opt_aS) and ($cov_aL >= $opt_aL) ) {
        push(@blhits, [$id1, $iden, $p->{alnln}, $exp1, $frame]); 
      }
    }
    return @blhits;
  } #### END if ($g_iden == 0 )
  else { #### Global idnetity
    if (($blast_prog eq "blastn") and $circle) { reset_alignment_coor_for_circle_seq($bl); }
    #### get colinear non-overlapping HSPs
    my @hsp = (); #### [id, len, qfrom, qend, sbegin, send, expect]
    my $iden_letters = 0;
    my $aln_letters = 0;
    my @aln_lens = ();
    my $hsp_no = 0;
    for ($i=0; $i<$bl->{no}; $i++) {
      my $p = $bl->{sbj}->[$i];
      my ($id1, $len_sub) = split(/\./, $p->{id});
      my $frame = $p->{frame};
      if (not $len_rep) {$len_rep = (split(/\./,$p->{qid}))[1]; }

      if ($hsp_no) {
        if ($id1 ne $hsp[0]->[0]) {
          #### 1. parse previous subject's HSPs
          my $iden       = int($iden_letters / $hsp[0]->[1] * 10000)/100; 
          my $cov_aS     = $aln_letters  / $hsp[0]->[1];
          my $cov_aL     = $aln_letters  / $len_rep;
          my $exp1       = $hsp[0]->[6];
          my $frame      = $hsp[0]->[7];
  
          if (($iden/100 > $NR_clstr or $exp1<$NR_clstre) and ($cov_aS >= $opt_aS) and ($cov_aL >= $opt_aL) ) {
            #push(@blhits, [$hsp[0]->[0], $iden, $aln_letters, $exp1, $frame]);
            push(@blhits, [$hsp[0]->[0], $iden, join(":", @aln_lens), $exp1, $frame]);
          }
          #### 2. init some values
          @hsp = ();
          $iden_letters = 0;
          $aln_letters = 0;
          @aln_lens = ();
          $hsp_no = 0;
        }
      }

      #check whether overlap with previous high score HSPs
      my $overlap_flag = 0;
      for ($j=0; $j<$hsp_no; $j++) {
        if (overlap1($p->{qfrom}, $p->{qend}, $hsp[$j]->[2], $hsp[$j]->[3])) { $overlap_flag = 1; last; }
        if (overlap1($p->{sfrom}, $p->{send}, $hsp[$j]->[4], $hsp[$j]->[5])) { $overlap_flag = 1; last; }
      }
      next if ($overlap_flag);

      #check whether this HSP cross with previous high score HSPs
      my $cross_flag = 0;
      for ($j=0; $j<$hsp_no; $j++) {
        if (cross1($p->{qfrom}, $p->{qend}, $hsp[$j]->[2], $hsp[$j]->[3],
                   $p->{sfrom}, $p->{send}, $hsp[$j]->[4], $hsp[$j]->[5])) {
          $cross_flag = 1; last;
        }
      }
      next if ($cross_flag);

      push(@hsp, [$id1, $len_sub, $p->{qfrom}, $p->{qend}, $p->{sfrom}, $p->{send}, $p->{expect}, $p->{frame}]);
      $iden_letters += int($p->{iden} * $p->{alnln} / 100);
      $aln_letters += $p->{alnln};
      push(@aln_lens, $p->{alnln});
      $hsp_no++;
    }

      if ($hsp_no) { #last record 
        #### 1. parse previous subject's HSPs
        my $iden       = int($iden_letters / $hsp[0]->[1] * 10000)/100;
        my $cov_aS     = $aln_letters  / $hsp[0]->[1];
        my $cov_aL     = $aln_letters  / $len_rep;
        my $exp1       = $hsp[0]->[6];
        my $frame      = $hsp[0]->[7];

        if (($iden/100 > $NR_clstr or $exp1<$NR_clstre) and ($cov_aS >= $opt_aS) and ($cov_aL >= $opt_aL) ) {
          #push(@blhits, [$hsp[0]->[0], $iden, $aln_letters, $exp1, $frame]);
          push(@blhits, [$hsp[0]->[0], $iden, join(":", @aln_lens), $exp1, $frame]);
        }
      }

    return @blhits;
  }
}
########## END process_blout_blastp_blastn


sub overlap1 {
  my ($b1, $e1, $b2, $e2) = @_;

  my $t; ### 
  if ($e1 < $b1) { $t  = $e1; $e1 = $b1; $b1 = $t; }
  if ($e2 < $b2) { $t  = $e2; $e2 = $b2; $b2 = $t; }

  return 0 if ($e2 < $b1);
  return 0 if ($b2 > $e1);
  return ( ($e1<$e2)? $e1:$e2 )-( ($b1>$b2)? $b1:$b2);
}
########## END overlap1

## modified on 2013_0818 to hancle +- frames
sub cross1 {
  my ($q_b1, $q_e1, $q_b2, $q_e2,
      $s_b1, $s_e1, $s_b2, $s_e2) = @_;

  my $fr_q1 = ($q_b1 < $q_e1) ? 1 : -1;
  my $fr_q2 = ($q_b2 < $q_e2) ? 1 : -1;
  my $fr_s1 = ($s_b1 < $s_e1) ? 1 : -1;
  my $fr_s2 = ($s_b2 < $s_e2) ? 1 : -1;

  my $fr1 = $fr_q1 * $fr_s1;
  my $fr2 = $fr_q2 * $fr_s2;
  return 1 if (($fr1 * $fr2) < 0); # one ++ and one +-

  my $t;
  if ($q_e1 < $q_b1) { $t    = $q_e1; $q_e1 = $q_b1; $q_b1 = $t; }
  if ($q_e2 < $q_b2) { $t    = $q_e2; $q_e2 = $q_b2; $q_b2 = $t; }
  if ($s_e1 < $s_b1) { $t    = $s_e1; $s_e1 = $s_b1; $s_b1 = $t; }
  if ($s_e2 < $s_b2) { $t    = $s_e2; $s_e2 = $s_b2; $s_b2 = $t; }

# after above transformation
#                               0           q_b1           q_e1             q_b2        q_e2       qlen
# query                      5' ====================================================================
# match                                     ||||||||||||||||                |||||||||||||
# subject                         5' ========================================================================>>>>>> frame +
#                                    0      s_b1           s_e1             s_b2        s_e2                 slen

# match                                     ||||||||||||||||                |||||||||||||
# subject                         3' ========================================================================>>>>>> frame -
#                                    slen   s_e1           s_b1             s_e2        s_b2                 0   

  if (($fr1 > 0) and ($fr2>0)) { # both ++
    return ( (($q_b2-$q_b1)*($s_b2-$s_b1) <0) ? 1 : 0);
  }
  else { # both --
    return ( (($q_b2-$q_b1)*($s_e1-$s_e2) <0) ? 1 : 0);
  }

}
########## END cross1


## modified on 2013_0818 to hancle +- frames
sub cross1_before_2013_0818 {
  my ($q_b1, $q_e1, $q_b2, $q_e2,
      $s_b1, $s_e1, $s_b2, $s_e2) = @_;

  my $t;
  if ($q_e1 < $q_b1) { $t    = $q_e1; $q_e1 = $q_b1; $q_b1 = $t; }
  if ($q_e2 < $q_b2) { $t    = $q_e2; $q_e2 = $q_b2; $q_b2 = $t; }
  if ($s_e1 < $s_b1) { $t    = $s_e1; $s_e1 = $s_b1; $s_b1 = $t; }
  if ($s_e2 < $s_b2) { $t    = $s_e2; $s_e2 = $s_b2; $s_b2 = $t; }

  return ( (($q_b2-$q_b1)*($s_b2-$s_b1) <0) ? 1 : 0);
}
########## END cross1

sub readblast_m8 {
  my ($i, $j, $k, $ll, $no); 
  my ($q_seq, $filename) = @_;


  my $fh  = "BL" ;
  if ($bl_STDIN) {      $fh = "STDIN"; }
  else           { open($fh, $filename) || return; }

  my @this_sbj = ();
  $no = 0;
  while($ll = <$fh>) {
    chop($ll);
    my @lls = split(/\t/,$ll);
    my $frame = "";
       $frame .= ($lls[6] < $lls[7]) ? "+" : "-";
       $frame .= ($lls[8] < $lls[9]) ? "+" : "-";
    $this_sbj[$no] = {
      'qid'     => $lls[0],
      'id'      => $lls[1],
      'iden'    => $lls[2],
      'alnln'   => $lls[3],
      'ms'      => $lls[4],
      'gap'     => $lls[5],
      'qfrom'   => $lls[6],
      'qend'    => $lls[7],
      'sfrom'   => $lls[8],
      'send'    => $lls[9],
      'expect'  => $lls[10],
      'score'   => $lls[11],
      'frame'   => $frame,
    };

    $no++;
# BLASTP 2.2.24 [Aug-08-2010]
# Query: gi|388328107|pdb|4DDG|A Chain A, Crystal Structure Of Human Otub1UBCH5B~UBUB
# Database: pdbaa.fa
# Fields: Query id, Subject id, % identity, alignment length, mismatches, gap openings, q. start, q. end, s. start, s. end, e-value, bit score
#gi|388328107|pdb|4DDG|A gi|388328107|pdb|4DDG|A 91.81   171     9       3       6       171     1       171     6e-89    323
#gi|388328107|pdb|4DDG|A gi|388328107|pdb|4DDG|A 96.51   86      3       0       235     320     155     240     2e-41    166
  }
  close($fh) if (not $bl_STDIN);
              
  my $self = {
    'no'  => $no,
    'sbj' => [@this_sbj],
  };
  return $self;
}
########## END readblast_m8


sub blast_formatdb {
  my ($i0, $i, $j, $k, $len1);

  open(FDB, "> $tmp_db") || die;
  $j = 0;
  $len1 = 0;
  for ($i0=$NR_no-1; $i0>=0; $i0--) { ### from shortest to longest
    $i = $NR_idx[$i0];
    last if ($idens[$i] eq "*"); ### last if reach rep
    next if ($passeds[$i] and ($opt_g==0));
    my $seq = $seqs[$i];
    $seq =~ s/(.{70})/$1\n/g;
    $seq =~ s/\n$//;
    #print FDB ">$i $dess[$i]\n$seq\n";
    print FDB ">$i.$lens[$i]\n$seq\n";
    $j++;
    $len1 += $lens[$i];
  }
  close(FDB);

  while(1) {
    opendir(SEQDB, $seq_dir) || next;
    my @leftseqs = grep {/lock/} readdir(SEQDB);
    closedir(SEQDB);
                                                                                       
    last unless @leftseqs;
    sleep(3);
  }

  return(0, 0) unless ($j > 0);

  my $cmd_line = "$formatdb -i $tmp_db";
     $cmd_line = "$formatdb -in $tmp_db" if ($bl_plus);
  my $cmd = `$cmd_line`;
     
  ((-e "$tmp_db.phr") and (-e "$tmp_db.pin") and (-e "$tmp_db.psq")) ||
  ((-e "$tmp_db.nhr") and (-e "$tmp_db.nin") and (-e "$tmp_db.nsq")) ||
  ((-e "$tmp_db.00.phr") and (-e "$tmp_db.00.pin") and (-e "$tmp_db.00.psq")) ||
  ((-e "$tmp_db.00.nhr") and (-e "$tmp_db.00.nin") and (-e "$tmp_db.00.nsq"))
     || die "Can not formatdb";

  return($j, $len1);
}
########## END blast_formatdb


sub remove_blast_db {
  my ($i, $j, $k);
  $cmd = `rm -f $tmp_db`;
  $cmd = `rm -f $tmp_db.p*`;
  $cmd = `rm -f $tmp_db.n*`;

  return;
}
########## END remove_blast_db


my $common_usage = <<EOD;

Options 
  input/output:
    -i  in_dbname, required
    -o  out_dbname, required
    -l  length_of_throw_away_sequences, default 10

  thresholds:
    -c  clustering threshold (sequence identity), default 0.3
    -ce clustering threshold (blast expect), default -1, 
        it means by default it doesn't use expect threshold, 
        but with positive value, the program cluster seqs if similarities
        meet either identity threshold or expect threshold 
    -G  (1/0) use global identity? default 1
        two sequences Long (i.e. representative) and Short (redunant) may have multiple
        alignment fragments (i.e. HSPs), see:
        seq1  xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx   Long sequence
                   ||||||||||||||||||             /////////////          i.e. representative
                   ||||||||||||||||||            /////////////                sequence
                   ||||||||HSP 1 ||||           ////HSP 2 ///
                   ||||||||||||||||||          /////////////
                   ||||||||||||||||||         /////////////
        seq2    xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx          Short sequence
                   <<  length 1    >>        <<   len 2 >>               i.e. redundant
                <<<<<<<<<<<< length of short sequence >>>>>>>>>>>>>>          sequence

                          total identical letters from all co-linear and non-overlapping HSPs
        Glogal identity = -------------------------------------------------------------------
                                        length of short sequence
        Local identity  = identity of the top high score HSP
        if you prefer to use -G 0, it is suggested that you also
        use -aS, -aL, such as -aS 0.8, to prevent very short matches.
    -aL	alignment coverage for the longer sequence, default 0.0
 	if set to 0.9, the alignment must covers 90% of the sequence
    -aS	alignment coverage for the shorter sequence, default 0.0
 	if set to 0.9, the alignment must covers 90% of the sequence
    -g  (1/0), default 0
        by cd-hit's default algorithm, a sequence is clustered to the first 
        cluster that meet the threshold (fast cluster). If set to 1, the program
        will cluster it into the most similar cluster that meet the threshold
        (accurate but slow mode)
        but either 1 or 0 won't change the representatives of final clusters
    -circle (1/0), default 0
        when set to 1, treat sequences as circular sequence.
        bacterial genomes, plasmids are circular, but their genome coordinate maybe arbitary, 
        the 2 HSPs below will be treated as non co-linear with -circle 0
        the 2 HSPs below will be treated as     co-linear with -circle 1
              -------------circle-----------    
              |                            |   
        seq1  xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx      genome / plasmid 1 
               \\\\\\\\      /////////////         
                \\\\\\\\    /////////////                
                  HSP 2 -> ////HSP 1 ///   <-HSP 2
                          /////////////     \\\\\\\\
                         /////////////       \\\\\\\\
        seq2           xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx   genome / plasmid 2
                       |                             |
                       -----------circle--------------
    -sl, length of very long sequences to be skipped, default 0, no skipping
        e.g. -sl 5000 means sequences longer than 5000 aa will be treated as singleton clusters
             without clustering, to save time, especially when there is -aL option in place, very
             long sequences will not be clustered anyway.
   program:
     -prog (blastp, blastn, megablast, blastpgp), default blastp 
     -p  profile search para, default
           "-j 3 -F F -e 0.001 -b 500 -v 500"
     -dprof database for building PSSM, default using input
         you can also use another database that is more comprehensive like NR80
     -s  blast search para, default
           "-F F -e 0.000001 -b 100000 -v 100000"
     -bs (1/0) default 1
        pipe blast results from into parser instead of save in hard drive (save time)

   compute:
     -exec (qsub, local) default local
          this program writes a shell script to run blast, this script is
          either performed locally by sh or remotely by qsub
          with qsub, you can use PBS, SGE etc
     -host number of hosts, ie number of qsub jobs 
     -para number of parallel blast job per qsub job (each blast can use multi cores), default 1
     -blp  number of threads per  blast job, default 1
           number of threads per blast job X number of parallel blast job per qsub job
           should <= the number of cores in your computer
           if your computer grid has 32 cores / node, do either of the followings
           -para 4  -blp 8
           -para 8  -blp 4
           -para 16 -blp 2
           -para 32 -blp 1
     -shf a filename for add local settings into the job shell script
          for example, when you run PBS jobs, you can add quene name etc in this
          file and this script will add them into the job shell script
e.g. template file for PBS
#!/bin/sh
#PBS -v PATH
#PBS -l walltime=8:00:00
#PBS -q job_queue.q

e.g. template file for SGE or OGE
#!/bin/sh
#\$ -v PATH
#\$ -q job_queue.q 
#\$ -V
#\$ -pe orte 8

  job:
    -rs steps of save restart file and clustering output, default 5000
        everytime after process 5000 sequences, program write a 
        restart file and current clustering information
    -restart restart file, readin a restart file
        if program crash, stoped, termitated, you can restart it by
        add a option "-restart sth.restart"
    -rf steps of re format blast database, default 200,000
        if program clustered 200,000 seqs, it remove them from seq
        pool, and re format blast db to save time
    -J  job, job_file, exe specific jobs like parse blast outonly
        DO NOT use it, it is only used by this program itself
    -k (1/0) keep blast raw output file, default $keep_bl

    -P path to executables
EOD


sub print_usage {
  print <<EOD;
Usage psi-cd-hit [Options] 
$common_usage

                                    ==============================
                                    by Weizhong Li, liwz\@sdsc.edu
                                    ==============================
    If you find cd-hit useful, please kindly cite:

    "Clustering of highly homologous sequences to reduce thesize of large protein database", Weizhong Li, Lukasz Jaroszewski & Adam GodzikBioinformatics, (2001) 17:282-283
    "Cd-hit: a fast program for clustering and comparing large sets of protein or nucleotide sequences", Weizhong Li & Adam Godzik Bioinformatics, (2006) 22:1658-1659

EOD
  return;
}
########## END print_usage


## like above, but don't assign seqs to specific node
## while let nodes run them autoly
sub  run_batch_blast3 {
  my $i0 = shift;
  my ($id, $i, $j, $k);
 
  my $total_jobs = $batch_no_per_node * $num_qsub * $para_no;

  for ($k=0; $i0<$NR_no; $i0++) {
    $id = $NR_idx[$i0];
    next if ($passeds[$id]);
    next if ($in_bg[$id]);
    $in_bg[$id] = 1;

    my $seq = $seqs[$id];
    open(SEQ, "> $seq_dir/$id") || die "Can not write";
    #print SEQ "$dess[$id]\n$seq\n";
    print SEQ ">$id.$lens[$id]\n$seq\n";
    close(SEQ);
    $k++;
    last if ($k >= $total_jobs);
  }

  if ($exec_mode eq "qsub") {
    for ($j=0; $j<$num_qsub; $j++) {
      my $t = "psi-cd-hit-$j";
      print LOG "PBS querying $j\n";
      my $cmd = `qsub -N $t $remote_sh_script`;
    }
  }
  elsif ($exec_mode eq "local") {
    my $cmd = `sh $remote_sh_script >/dev/null 2>&1 &`;
  }

  return;
} 
########## END run_batch_blast3


sub write_remote_sh_script {
  my ($i, $j, $k);
  my $local_sh = <<EOD;
#!/bin/sh
#PBS -v PATH
#\$ -v PATH
EOD

  if ($sh_file) {
    $local_sh = `cat $sh_file`;
  }

  open(RESH, "> $remote_sh_script") || die;
  print RESH <<EOD;
$local_sh

cd $pwd
EOD

  for ($k=0; $k<$para_no; $k++){
    print RESH "./$remote_perl_script $k&\n"
  }
  print RESH "wait\n\n";

  close(RESH);
  return;
}
########## END write_remote_sh_script

sub write_remote_perl_script {
  my $dir1 = ".";
  my $bl2  = "$blast_exe -d $dir1/$tmp_db $bl_para";
     $bl2  = "$blast_exe -db $dir1/$tmp_db $bl_para" if ($bl_plus);

  my $opti = "-i"; $opti = "-query" if ($bl_plus);
  my $opto = "-o"; $opto = "-out"   if ($bl_plus);

  open(REPERL, "> $remote_perl_script") || die;
  print REPERL <<EOD;
#!/usr/bin/perl
\$host = shift;
\$arg = shift;

#### random sleep, rand() can be a fraction of second
select(undef,undef,undef,rand());

if (\$arg) {
  \@ids = split(/,/, \$arg);
}
else {
  while(1) {
    if (opendir(DDIR, "$seq_dir")) { 
      \@ids = grep {/^\\d+\$/} readdir(DDIR);
      last;
    }
    else {
      sleep(1);
    }
  }
}

foreach \$id (\@ids) {

  next unless (-e "$seq_dir/\$id");
  next if (-e "$seq_dir/\$id.lock");
  \$cmd = `touch $seq_dir/\$id.lock`;

  if ($bl_STDIN) {
    \$cmd = `$bl2 $opti $seq_dir/\$id | $script_name -J parse_blout $bl_dir/\$id -c $NR_clstr -ce $NR_clstre -aS $opt_aS -aL $opt_aL -G $g_iden -prog $blast_prog -bs 1`;
  }
  else {
    \$cmd = `$bl2 $opti $seq_dir/\$id $opto $bl_dir/\$id`;
    \$cmd =                         `$script_name -J parse_blout $bl_dir/\$id -c $NR_clstr -ce $NR_clstre -aS $opt_aS -aL $opt_aL -G $g_iden -prog $blast_prog -bs 0`;
  }
  \$cmd = `rm -f  $seq_dir/\$id`;
  \$cmd = `rm -f  $seq_dir/\$id.lock`;
}

(\$tu, \$ts, \$cu, \$cs) = times();
\$tt = \$tu + \$ts + \$cu + \$cs;
\$cmd = `echo \$tt >> $seq_dir/host.\$host.cpu`;

EOD
  close(REPERL);
  my $cmd = `chmod 755 $remote_perl_script`;

  return;
} 
########## END write_remote_perl_script


sub wait_blast_out {
  my $out = shift;
  print LOG "waiting for $out";
  while(1) {
    if (-e $out) {
      my $last = `tail -1 $out`;
      chop($last);
      last if ($last =~ /^#$/);
    }
    sleep(1);
    print LOG ".";
  }
  print LOG "\n";

  return;
}
########## END wait_blast_out



1;

