sub inc { $_[0]++ } my $x=1; inc(do { $x }); print "$x\n";
