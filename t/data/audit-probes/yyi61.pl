sub outer { my $x = shift; my $in = sub { $x * 2 }; $in->() + inner($x) } sub inner { $_[0] + 1 } print outer(1), outer(5), "\n";
