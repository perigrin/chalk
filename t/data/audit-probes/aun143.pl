my $c = 0; my $inc = sub { $c++ }; my $get = sub { $c }; $inc->() for 1..3; print $get->(), " $c\n";
