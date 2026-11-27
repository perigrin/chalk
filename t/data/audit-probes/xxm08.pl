my %h; for my $k (qw(a b)) { $h{$k} = \$k } print join(",", map { ${$h{$_}} } sort keys %h), "\n";
