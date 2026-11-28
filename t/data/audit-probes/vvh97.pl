my %h = (a=>1); eval { for my $v (values %h) { $v = 5; die "x\n" } }; print $h{a}, "\n";
