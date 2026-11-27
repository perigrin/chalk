my @a = (1,2); undef $a[0]; my %h = (k=>1); undef $h{k}; print defined $a[0] ? "d" : "u", exists $h{k} ? "e" : "n", "\n";
