my @a=(1,2); for my $x (@a) { undef $x } print defined $a[0] ? "d" : "u", "\n";
