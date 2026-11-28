my %h; my @l = (@h{qw(a b)} = (1)); print scalar(@l), defined $h{b} ? "d" : "u", exists $h{b} ? "e" : "n", "\n";
