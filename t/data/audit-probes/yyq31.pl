eval { $@ = "preset\n"; die }; print $@ =~ /^preset\n\t\.\.\.propagated/ ? "prop" : "other", "\n";
