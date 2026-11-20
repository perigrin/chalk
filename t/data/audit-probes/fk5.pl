my %h; my @a = (1); if (!@a) { @h{qw(a b)} = (1, 2) } print scalar(keys %h), "\n"; if (@a) { @h{qw(a b c)} = (1, 2, 3) } print scalar(keys %h), "\n";
