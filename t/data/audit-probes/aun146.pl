sub noop { 1 } my %h; noop($h{n}); print exists $h{n} ? "y" : "n", "\n";
