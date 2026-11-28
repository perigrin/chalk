my %h = (k => "ab"); s/a/z/ for values %h; print "$h{k}\n";
