sub b { $_[0] .= "x" } my @a=(1,2); for my $e (@a) { b($e); last if $e eq "1x" } print "@a\n";
