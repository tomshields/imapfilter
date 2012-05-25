#!/usr/local/bin/perl
#
# Copyright (c) 1997-1998 Kevin Johnson <kjj@pobox.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.
#
# $Id: IMAP.pm,v 1.1 1998/12/01 02:13:52 ts Exp $

require 5.004;

package Net::IMAP;

use strict;

=head1 NAME

Net::IMAP - A client interface to the Internet Message Access Protocol
(IMAP).

C<WARNING: This code is in alpha release.  Expect the interface to change.>

=cut

use IO::Socket;
use Net::xAP qw($xAP_ATOM $xAP_ASTRING $xAP_PARENS);
use Carp;
use Data::Dumper;

use vars qw($VERSION @ISA $SEQUENCE);

@ISA = qw(Net::xAP IO::Socket::INET);

=head1 SYNOPSIS

C<use Net::IMAP;>

=head1 DESCRIPTION

C<Net::IMAP> provides a perl interface to the client portion of the
Internet Message Access Protocol (IMAP).

=head1 METHODS

=cut

my $Debug = 0;

my %_system_flags = (
		     '\Seen' => 1,
		     '\Answered' => 1,
		     '\Flagged' => 1,
		     '\Deleted' => 1,
		     '\Recent' => 1,
		    );

sub new {
  my $class = shift;
  my $type = ref($class) || $class;
  my $host = shift if @_ % 2;
  my %options = @_;
  
  $options{Debug} ||= $Debug;
  
  my $self = Net::xAP->new($host, 'imap2(143)', Timeout => 10, %options)
    or return undef;
  
  bless $self, $class;
  
  $self->{Options} = {%options};
  
  $self->{PreAuth} = 0;
  $self->{Banner} = undef;
  $self->{Capabilities} = ();
  $self->{Mailbox} = ();
  $self->{DefaultCallback} = $self->default_callback;
  
  STDERR->autoflush(1);
  
  $self->_get_banner or return undef;
  
  my $resp;
  if (defined($self->{Options}{Synchronous}) &&
      $self->{Options}{Synchronous}) {
    $resp = $self->capability;
  } else {
    $self->capability;
    $resp = $self->response;
  }
  if ($resp->status ne 'OK') {
    carp "capability command failed on initial connection";
    $self->connection->close or carp "error closing connection: $!";
    $! = 5;			# *sigh* error reporting needs to be improved
    return undef;
  }
  
  return $self;
}

# hide the password from the debug output.
sub debug_text { $_[2] =~ /^(\d+ LOGIN [^\s]+)/i ? "$1 ..." : $_[2] }

sub _get_banner {
  my $self = shift;
  
  my $list = $self->getline or return undef;
  
  $self->debug_print(0, join(' ', @{$list})) if $self->debug;
  
  if (($list->[0] eq '*') && ($list->[1] =~ /^PREAUTH$/i)) {
    $self->{PreAuth}++;
  } elsif (($list->[0] ne '*') || ($list->[1] !~ /^OK$/i)) {
    return undef;
  }
  my $found_it = 0;
  for my $item (@{$list}) {
    $found_it++ if ($item =~ /^IMAP4/i);
  }
  unless ($found_it) {
    $self->connection->close;
    return undef;
  }
  
  $self->{Banner} = $list;
  
  return 1;
}
###############################################################################
sub preauth { return shift->{PreAuth} }
sub banner { return shift->{Banner} }
###############################################################################
# noop
sub noop { $_[0]->command($_[0]->generic_callback, 'noop') }

# capability
sub capability {  $_[0]->command($_[0]->capability_callback, 'capability') }

sub has_capability { return defined($_[0]->{Capabilities}{$_[1]}) }

# logout
sub logout { $_[0]->command($_[0]->logout_callback, 'logout') }

# authenticate AUTHTYPE @BASE64GOO
# sub authenticate { shift->command(sub {0}, 'authenticate', @_) }

# login USER PASSWORD
sub login {
  $_[0]->command($_[0]->generic_callback,
		 'login', $xAP_ASTRING => $_[1], $xAP_ASTRING => $_[2]);
}

# select MAILBOX
sub select {
  $_[0]->command($_[0]->select_callback, 'select', $xAP_ASTRING => $_[1]);
}

# examine MAILBOX
sub examine {
  $_[0]->command($_[0]->select_callback, 'examine', $xAP_ASTRING => $_[1]);
}

# create MAILBOX
sub create {
  $_[0]->command($_[0]->generic_callback, 'create', $xAP_ASTRING => $_[1]);
}

# delete MAILBOX
sub delete {
  $_[0]->command($_[0]->generic_callback, 'delete', $xAP_ASTRING => $_[1]);
}

# rename MAILBOX MAILBOX
sub rename {
  $_[0]->command($_[0]->generic_callback,
		 'rename', $xAP_ASTRING => $_[1], $xAP_ASTRING => $_[2]);
}

# subscribe MAILBOX
sub subscribe {
  $_[0]->command($_[0]->generic_callback, 'subscribe', $xAP_ASTRING => $_[1]);
}

# unsubscribe MAILBOX
sub unsubscribe {
  $_[0]->command($_[0]->generic_callback,
		 'unsubscribe', $xAP_ASTRING => $_[1]);
}

# list REFNAME REGEXMAILBOXLIST
sub list {
  my $self = shift;
  my @args;
  push @args, $xAP_ASTRING => shift; # REFNAME
  for my $item (@_) {		# REGEXMAILBOXLIST
    push @args, $xAP_ASTRING => $item;
  }
  $self->command($self->list_callback('LIST'), 'list', @args);
}

# lsub REFNAME @REGEXMAILBOXLIST
sub lsub {
  my $self = shift;
  my @args;
  push @args, $xAP_ASTRING => shift; # REFNAME
  for my $item (@_) {		# REGEXMAILBOXLIST
    push @args, $xAP_ASTRING => $item;
  }
  $self->command($self->list_callback('LSUB'), 'list', @args);
}

# status MAILBOX @STATUSATTRS
sub status {
  my $self = shift;
  $self->command($self->status_callback($_[0]),
		 'status', $xAP_ASTRING => shift, $xAP_PARENS => [@_]);
}

# append MAILBOX [FLAGLIST] [DATETIMESTRING] MESSAGELITERAL
sub append {
  my $self = shift;
  my $mailbox = shift;
  my $lit = shift;
  my %options = @_;
  my @args;
  
  push @args, $xAP_ASTRING => $mailbox;

  if (defined($options{Flags})) {
    for my $flag (@{$options{Flags}}) {
      unless ($self->_valid_flag($flag)) {
	carp "$flag is not a system flag";
	return undef;
      }
    }
    push @args, $xAP_PARENS => [@{$options{Flags}}];
  }
  push @args, $xAP_ATOM => "\"$options{Date}\"" if (defined($options{Date}));
  # the next was a problem for someone - not sure what the problem was
  # $lit =~ s/$/\r/mg;
  push @args, $xAP_ASTRING => $lit;
  
  $self->command($self->generic_callback, 'append', @args);
}

# check
sub check { $_[0]->command($_[0]->generic_callback, 'check') }

# close
sub close { $_[0]->command($_[0]->close_callback, 'close') }

# expunge
sub expunge { $_[0]->command($_[0]->expunge_callback, 'expunge') }

# search [charset $xAP_ASTRING] @SEARCHKEYS
sub search {
  my $self = shift;
  my @args;
  if ($_[0] =~ /^CHARSET$/i) {
    shift;
    my $charset = shift;
    push @args, $xAP_ATOM => 'CHARSET', $xAP_ASTRING => $charset;
  }
  for my $item (@_) {
    push @args, $xAP_ATOM => $item;
  }
  $self->command($self->search_callback, 'search', @args);
}

# fetch MSGSET all|full|fast|FETCHATTR|@FETCHATTRS
sub fetch {
  my $self = shift;
  my $msgset = shift;
  my @args;
  if (scalar(@_) == 1) {
    push @args, $xAP_ATOM => shift;
  } else {
    push @args, $xAP_PARENS => [@_];
  }
  $self->command($self->fetch_callback, 'fetch', $xAP_ATOM => $msgset, @args);
}

# store MSGSET ITEMNAME @STOREATTRFLAGS
sub store {
  my $self = shift;
  my $msgset = shift;
  my $itemname = shift;
  for my $flag (@_) {
    unless ($self->_valid_flag($flag)) {
      carp "$flag is not a system flag";
      return undef;
    }
  }
  $self->command($self->store_callback, 'store',
		 $xAP_ATOM => $msgset, $xAP_ATOM => $itemname,
		 $xAP_PARENS => [@_]);
}

# copy MSGSET MAILBOX
sub copy {
  $_[0]->command($_[0]->generic_callback,
		 'copy', $xAP_ATOM => $_[1], $xAP_ASTRING => $_[2]);
}

# uid copy MSGSET MAILBOX
sub uid_copy {
  $_[0]->command($_[0]->generic_callback,
		 'uid copy', $xAP_ATOM => $_[1], $xAP_ASTRING => $_[2]);
}

# uid fetch MSGSET all|full|fast|FETCHATTR|@FETCHATTRS
sub uid_fetch {
  my $self = shift;
  my $msgset = shift;
  my @args;
  if (scalar(@_) == 1) {
    push @args, $xAP_ATOM => shift;
  } else {
    push @args, $xAP_PARENS => [@_];
  }
  $self->command($self->fetch_callback,
		 'uid fetch', $xAP_ATOM => $msgset, @args);
}

# uid search [charset $xAP_ASTRING] @SEARCHKEYS
sub uid_search {
  my $self = shift;
  my @args;
  if ($_[0] =~ /^CHARSET$/i) {
    shift;
    my $charset = shift;
    push @args, $xAP_ATOM => 'CHARSET', $xAP_ASTRING => $charset;
  }
  for my $item (@_) {
    push @args, $xAP_ATOM => $item;
  }
  $self->command($self->search_callback, 'uid search', @args);
}

# uid store MSGSET ITEMNAME @STOREATTRFLAGS
sub uid_store {
  my $self = shift;
  my $msgset = shift;
  my $itemname = shift;
  for my $flag (@_) {
    unless ($self->_valid_flag($flag)) {
      carp "$flag is not a system flag";
      return undef;
    }
  }
  $self->command($self->store_callback, 'uid store',
		 $xAP_ATOM => $msgset, $xAP_ATOM => $itemname,
		 $xAP_PARENS => [@_]);
}
###############################################################################
# setacl MAILBOX IDENTIFIER MODRIGHTS
sub setacl {
  my $self = shift;
  return undef unless $self->has_capability('ACL');
  $self->command($self->generic_callback, 'setacl', $xAP_ASTRING => $_[0],
		 $xAP_ASTRING => $_[1], $xAP_ASTRING => $_[2]);
}

# getacl MAILBOX
sub getacl {
  my $self = shift;
  return undef unless $self->has_capability('ACL');
  $self->command($self->generic_callback, 'getacl', $xAP_ASTRING => $_[0]);
}

sub getacl_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Response->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') && ($list->[1] =~ /^ACL$/i)) {
      my @list2 = @{$list};
      my @sublist = @list2[2..$#list2] || ();
      $resp->{ACLS}{$list->[2]} = {@sublist};
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}

# deleteacl MAILBOX IDENTIFIER
sub deleteacl {
  my $self = shift;
  return undef unless $self->has_capability('ACL');
  $self->command($self->generic_callback,
		 'deleteacl', $xAP_ASTRING => $_[0], $xAP_ASTRING => $_[0]);
}

# listrights MAILBOX IDENTIFIER
sub listrights {
  my $self = shift;
  return undef unless $self->has_capability('ACL');
  $self->command($self->listrights_callback,
		 'listrights', $xAP_ASTRING => $_[0], $xAP_ASTRING => $_[0]);
}

sub listrights_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Response->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') && ($list->[1] =~ /^LISTRIGHTS$/i)) {
      my @list2 = @{$list};
      $resp->{LISTRIGHTS}{$list->[2]}{$list->[3]} = [@list2[4..$#list2]];
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}

# myrights MAILBOX
sub myrights {
  my $self = shift;
  return undef unless $self->has_capability('ACL');
  $self->command($self->myrights_callback, 'myrights', $xAP_ASTRING => $_[0]);
}

sub myrights_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Response->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') && ($list->[1] =~ /^MYRIGHTS$/i)) {
      $resp->{MYRIGHTS}{$list->[2]} = $list->[3];
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}
###############################################################################
# getquota QUOTAROOT
sub getquota {
  my $self = shift;
  return undef unless $self->has_capability('QUOTA');
  $self->command($self->quota_callback, 'getquota', $xAP_ASTRING => $_[0]);
}

# setquota QUOTAROOT SETQUOTALIST
sub setquota {
  my $self = shift;
  my $quotaroot = shift;
  return undef unless $self->has_capability('QUOTA');
  $self->command($self->quota_callback,
		 'getquota', $xAP_ASTRING => $quotaroot, $xAP_PARENS => [@_]);
}

sub quota_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Response->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') && ($list->[1] =~ /^QUOTA$/i)) {
      $resp->{QUOTA}{$list->[2]} = $list->[3];
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}

# getquotaroot MAILBOX
sub getquotaroot {
  my $self = shift;
  return undef unless $self->has_capability('QUOTA');
  $self->command($self->getquotaroot_callback,
		 'getquotaroot', $xAP_ASTRING => $_[0]);
}

sub getquotaroot_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Response->new;
  return sub {
    my $list = shift;
    # TODO 1st arg after QUOTA and could be an astring
    # TODO args after QUOTAROOT and could be astrings
    if ($list->[0] eq '*') {
      my @list2 = @{$list};
      if ($list->[1] =~ /^QUOTA$/i) {
	$resp->{QUOTA}{$list->[2]} = $list->[3];
      } elsif ($list->[1] =~ /^QUOTAROOT$/i) {
	$resp->{QUOTAROOT} = $list->[2];
      } else { return 0; }
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}
###############################################################################
sub generic_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Response->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') &&
	($list->[1] =~ /^OK$/i) &&
	($list->[2] =~ /^\[TRYCREATE\]$/i)) {
      # eat it for now
      return 1;
    }
    if ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    }
    return 0;
  }
}

sub capability_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Response->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') && ($list->[1] =~ /^CAPABILITY$/i)) {
      my @list2 = @{$list};
      for my $cap (@list2[2..$#list2]) {
	my $uccap = uc($cap);
	$self->{Capabilities}{$uccap}++;
	if ($uccap =~ /^AUTH=(.*)$/) {
	  $self->{AuthTypes}{$1}++;
	}
      }
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}

sub close_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Response->new;
  return sub {
    my $list = shift;
    if ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      $self->{Mailbox} = () if ($resp->status eq 'OK');
      return $resp;
    }
    return 0;
  }
}

sub select_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Response->new;

  # clean this up...
  $self->{Mailbox}{_EXISTS} = undef;
  $self->{Mailbox}{_RECENT} = undef;
  $self->{Mailbox}{_UIDVALIDITY} = undef;
  $self->{Mailbox}{_UNSEEN} = undef;
  $self->{Mailbox}{_PERMANENTFLAGS} = {};
  $self->{Mailbox}{_FLAGS} = {};
  
  return sub {
    my $list = shift;
    if ($list->[0] eq '*') {
      if (($list->[1] =~ /^\d+$/) && ($list->[2] =~ /^EXISTS$/i)) {
	$self->{Mailbox}{_EXISTS} = $list->[1];
      } elsif (($list->[1] =~ /^\d+$/) && ($list->[2] =~ /^RECENT$/i)) {
	$self->{Mailbox}{_RECENT} = $list->[1];
      } elsif ($list->[1] =~ /^OK$/i) {
	if ($list->[2] =~ /^\[UIDVALIDITY$/i) {
	  $list->[3] =~ s/\]$//;
	  $self->{Mailbox}{_UIDVALIDITY} = $list->[3];
	} elsif ($list->[2] =~ /^\[UNSEEN$/i) {
	  $list->[3] =~ s/\]$//;
	  $self->{Mailbox}{_UNSEEN} = $list->[3];
	} elsif ($list->[2] =~ /^\[PERMANENTFLAGS$/i) {
	  for my $flag (@{$list->[3]}) {
	    $self->{Mailbox}{_PERMANENTFLAGS}{$flag}++;
	  }
	} else { return 0 }
      } elsif ($list->[1] =~ /^FLAGS$/i) {
	for my $flag (@{$list->[2]}) {
	  $self->{Mailbox}{_FLAGS}{$flag}++;
	}
      } else { return 0 }
    } elsif ($list->[0] =~ /^\d+$/) {
	$resp->parse_status($list);
	if ($resp->status eq 'OK') {
	  # we've saved several values from untagged responses into temp
	  # locations until we knew that the command was OK.
	  $self->{Mailbox}{EXISTS} = $self->{Mailbox}{_EXISTS};
	  delete $self->{Mailbox}{_EXISTS};
	  $self->{Mailbox}{RECENT} = $self->{Mailbox}{_RECENT};
	  delete $self->{Mailbox}{_RECENT};
	  $self->{Mailbox}{UIDVALIDITY} = $self->{Mailbox}{_UIDVALIDITY};
	  delete $self->{Mailbox}{_UIDVALIDITY};
	  $self->{Mailbox}{UNSEEN} = $self->{Mailbox}{_UNSEEN};
	  delete $self->{Mailbox}{_UNSEEN};
	  $self->{Mailbox}{PERMANENTFLAGS} = {%{$self->{Mailbox}{_PERMANENTFLAGS}}};
	  delete $self->{Mailbox}{_PERMANENTFLAGS};
	  $self->{Mailbox}{FLAGS} = {%{$self->{Mailbox}{_FLAGS}}};
	  delete $self->{Mailbox}{_FLAGS};
	  # only set this if the command was OK
	  $self->{Mailbox}{READONLY} = ($resp->status_code eq 'READ-ONLY')?1:0;
	}
	return $resp;
    } else { return 0; }
    return 1;
  }
}

sub status_callback {
  my $self = shift;
  my $mailbox = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Status->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') &&
	($list->[1] =~ /^STATUS$/i) &&
	($list->[2] eq $mailbox)) {
      $resp->{Status}{$mailbox} = {@{$list->[3]}};
    } elsif ($list->[0] =~ /^\d$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}

sub expunge_callback {
  my $self = shift;
  my $mailbox = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Expunge->new;

  return sub {
    my $list = shift;
    if (($list->[0] eq '*') &&
	($list->[1] =~ /^\d+$/) &&
	($list->[2] =~ /^EXPUNGE$/i)) {
      push @{$resp->{List}}, $list->[1];
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}

sub search_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Search->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') && ($list->[1] =~ /^SEARCH$/i)) {
      my @list2 = @{$list};
      push @{$resp->{List}}, @list2[2..$#list2];
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}

sub store_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Store->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') &&
	($list->[1] =~ /^\d+$/) &&
	($list->[2] =~ /^FETCH$/i)) {
      my @list2 = @{$list->[3]};
      if ($list2[0] =~ /^FLAGS$/i) {
	$resp->{Flags} = [@list2[1..$#list2]];
      }
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}

sub fetch_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Fetch->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') &&
	($list->[1] =~ /^\d+$/) &&
	($list->[2] =~ /^FETCH$/i)) {
      # $resp->{Data} = $list->[3];
      push @{$resp->{Data}}, $list->[3];
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}

sub list_callback {
  my $self = shift;
  my $mode = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::List->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') &&
	($list->[1] =~ /^$mode$/i) &&
	(ref($list->[2]) eq 'ARRAY')) {
      push @{$resp->{Folders}}, {Flags => \@{$list->[2]},
				 Delim => $list->[3],
				 Name => $list->[4]};
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    } else { return 0; }
    return 1;
  }
}

sub logout_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMAP::Response->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') && ($list->[1] =~ /^BYE$/i)) {
      # need to claim it, but don't need to do anything with it since we'll
      # be getting a tagged response RSN.
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      $self->connection->close if ($resp->status eq 'OK');
      return $resp;
    } else { return 0; }
    return 1;
  }
}
###############################################################################
sub default_callback {
  my $self = shift;
  return sub {
    my $list = shift;
    if ($list->[0] eq '*') {
      if ($list->[1] =~ /^\d+$/) {
	if ($list->[2] =~ /^EXISTS$/i) {
	  $self->{Mailbox}{EXISTS} = $list->[1];
	} elsif ($list->[2] =~ /^RECENT$/i) {
	  $self->{Mailbox}{RECENT} = $list->[1];
	} elsif ($list->[2] =~ /^EXPUNGE$/i) {
	  # place holder;
	} else { return 0; }
      } elsif ($list->[1] =~ /^FLAGS$/i) {
	undef $self->{Mailbox}{FLAGS};
	for my $flag (@{$list->[2]}) {
	  $self->{Mailbox}{FLAGS}{$flag}++;
	}
      } elsif ($list->[1] =~ /^BYE$/i) {
	$self->connection->close;
      } elsif ($list->[1] =~ /^OK$/i) {
	if ($list->[2] =~ /^\[READ-(ONLY|WRITE)\]$/i) {
	  $self->{Mailbox}{READONLY} = ($1 eq 'WRITE') ? 0 : 1;
	} elsif ($list->[2] =~ /^\[UIDVALIDITY$/i) {
	  my $uidvalidity = $list->[3];
	  $uidvalidity =~ s/\]$//;
	  $self->{Mailbox}{UIDVALIDITY} = $uidvalidity;
	} elsif ($list->[2] =~ /^\[UNSEEN$/i) {
	  my $unseen = $list->[3];
	  $unseen =~ s/\]$//;
	  $self->{Mailbox}{UNSEEN} = $unseen;
	} elsif ($list->[2] =~ /^\[PERMANENTFLAGS$/i) {
	  undef $self->{Mailbox}{PERMANENTFLAGS};
	  for my $flag (@{$list->[3]}) {
	    $self->{Mailbox}{PERMANENTFLAGS}{$flag}++;
	  }
	} else { return 0; }
      } else { return 0; }
    } else { return 0; }
    return 1;
  }
}
###############################################################################
sub _valid_flag {
  return ((substr($_[1], 0, 1) ne "\\") || defined($_system_flags{$_[1]}));
}
###############################################################################
sub _dump_internals { print STDERR "----\n", Dumper($_[0]), "----\n" }
###############################################################################
package Net::IMAP::Response;
use vars qw(@ISA);
@ISA = qw(Net::xAP::Response);
###############################################################################
package Net::IMAP::List;
use vars qw(@ISA);
@ISA = qw(Net::IMAP::Response);
###############################################################################
package Net::IMAP::Fetch;
use vars qw(@ISA);
@ISA = qw(Net::IMAP::Response);
###############################################################################
package Net::IMAP::Status;
use vars qw(@ISA);
@ISA = qw(Net::IMAP::Response);
###############################################################################
package Net::IMAP::Expunge;
use vars qw(@ISA);
@ISA = qw(Net::IMAP::Response);
###############################################################################
package Net::IMAP::Search;
use vars qw(@ISA);
@ISA = qw(Net::IMAP::Response);
###############################################################################
package Net::IMAP::Store;
use vars qw(@ISA);
@ISA = qw(Net::IMAP::Response);
###############################################################################

1;
