eval { eval { die "a\n" }; die }; print $@ =~ /^a\n\t\.\.\.propagated/ ? "prop" : "no", "\n";
