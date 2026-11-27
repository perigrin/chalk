sub f { 1 } my %h; f($h{z}); print exists $h{z} ? "e" : "n", "\n";
