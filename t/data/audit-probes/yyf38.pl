my @a=(1,2,3); for my $x (@a) { chop(my $t = $x . "z"); $x = $t . $t } print "@a\n";
