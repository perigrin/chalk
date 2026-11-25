my %h; eval { my $x=$h{a}{b}{c}; die "x\n" }; print exists $h{a} ? 1 : 0, exists $h{a}{b} ? 1 : 0, "\n";
