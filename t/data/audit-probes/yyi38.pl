sub app { push @{$_[0]}, $_[1] } my @a=(1); app(\@a, 2); my $r=[]; app($r, 3); my %h; app($h{l} //= [], 4); print "@a@$r@{$h{l}}\n";
