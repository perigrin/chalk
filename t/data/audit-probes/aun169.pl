my %h; my $v = $h{a}{b}{c}; print join(",", sort keys %h), ":", join(",", keys %{$h{a}}), "\n";
