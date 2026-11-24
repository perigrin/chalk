sub clr { %{$_[0]}=() } my %h=(a=>1); my $v=$h{a}; clr(\%h); print $v, exists $h{a}?1:0, "\n";
