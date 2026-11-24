eval { die }; print $@ =~ /^Died/ ? "d" : "n", "\n";
