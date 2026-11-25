sub f {} my %h; f($h{a}{b}); print exists $h{a} ? 1 : 0, "\n";
