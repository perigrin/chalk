sub b { $_[0] .= "x"; 1 } my @a=(1,2); for my $e (@a) { last if b($e) && $e eq "1x" } print "@a\n";
