my @a; my $p=sub { push @a,@_ }; my $c=sub { scalar @a }; $p->(1); my $n=$c->(); $p->(2,3); print $n, $c->(), "\n";
