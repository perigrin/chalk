our $err = 0; sub chk { $err++ if $_[0] > 1 } for my $v (1..3) { chk($v) } print "$err\n";
