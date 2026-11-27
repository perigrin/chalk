my $x = 0; my $add = sub { $x += $_ for @_; $x }; $add->(1,2); $add->($x); print "$x\n";
