sub mk { my @a; sub { push @a, $_[0]; scalar @a } } my $c = mk(); my $d = mk(); $c->(1); print $c->(1), $d->(1), "\n";
