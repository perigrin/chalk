my %h; sub st { $h{$_[0]} = $_[1] } st(a => 1); my $v = $h{a}; st(a => 2); print "$v$h{a}\n";
