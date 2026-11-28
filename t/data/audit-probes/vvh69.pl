my $x = 5; eval { $x->method }; print $@ =~ /Can't (call|locate)/ ? "nomethod" : "no", "\n";
