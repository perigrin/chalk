our $x = 1; sub inc { $_[0]++ } inc($x); inc($main::x); print "$x\n";
