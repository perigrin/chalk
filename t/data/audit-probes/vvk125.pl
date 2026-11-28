sub st { $_[0]{$_[1]} = $_[2]; $_[0] } my %h; st(st(\%h, a => 1), b => 2); print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
