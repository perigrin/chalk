sub inc { $_[0]++ } my $s="1b"; inc(substr($s,0,1)); print "$s\n";
