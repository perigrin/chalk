sub mk { my @l; sub { push @l, shift; scalar @l } } my ($p,$q)=(mk(),mk()); $p->(1); $p->(1); print $q->(1), $p->(1), "\n";
