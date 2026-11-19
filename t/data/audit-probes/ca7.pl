my %h; sub set { $h{$_[0]} = $_[1] } set("a", 1); my $v = $h{a}; set("a", 2); print "$v $h{a}\n";
