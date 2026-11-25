sub id { return @_ } sub inc { $_[0]++ } my $x=1; inc(id($x)); print "$x\n";
