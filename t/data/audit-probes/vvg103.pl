my @st; my $push = sub { push @st, @_ }; my $pop = sub { pop @st }; $push->(1, 2, 3); $pop->(); print "@st\n";
