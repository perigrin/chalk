sub inc { $_[0]++ } my %h; inc($h{n}); print exists $h{n} ? "y$h{n}" : "n", "\n";
