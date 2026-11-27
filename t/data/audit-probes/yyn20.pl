eval { eval { die "first\n" }; die }; print $@ =~ /^first\n\t\.\.\.propagated at/ ? "prop" : "other:$@", "\n";
