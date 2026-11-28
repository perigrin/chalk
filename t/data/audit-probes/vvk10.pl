sub f { scalar(@_) } my @a = (1, 2); my %h = (a => 1); print f(@a, %h, (), 5), "\n";
