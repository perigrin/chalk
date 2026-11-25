my %h; for ($h{a}{b}) { } print join(",", sort keys %h), exists $h{a}{b} ? 1 : 0, "\n";
