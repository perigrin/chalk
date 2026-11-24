my %h; print %h ? "t":"f"; $h{a}=1; print %h ? "t":"f"; delete $h{a}; print %h ? "t":"f", "\n";
