my %h; $h{$_}{n}++ for qw(a b a); push @{$h{$_}{l}}, 1 for qw(a); print join(",", map { "$_$h{$_}{n}" . scalar(@{$h{$_}{l} || []}) } sort keys %h), "\n";
