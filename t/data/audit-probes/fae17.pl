my $n=0; sub f { $n++; die "x\n" if $n<3; $n } my $v; until (defined($v = eval { f() })) { } print "$v\n";
