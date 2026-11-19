my @st; sub push_it { push @st, @_; scalar @st } sub pop_it { pop @st } push_it(1,2); my $p = pop_it(); my $n = push_it(7); print "$p $n @st\n";
