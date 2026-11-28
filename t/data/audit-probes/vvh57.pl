sub t { die } eval { t() }; print $@ =~ /^Died/ ? "died" : "other", "\n";
