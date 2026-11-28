my %h; my $v = $h{a}{b}{c}; print join(",", sort keys %h), exists $h{a}{b} ? "e" : "n", "\n";
