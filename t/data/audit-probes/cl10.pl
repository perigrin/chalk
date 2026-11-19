my $c = 0; my $inc = sub { $c++ }; $inc->() for 1..3; print "$c\n";
