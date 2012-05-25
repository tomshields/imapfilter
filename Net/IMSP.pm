#!/usr/local/bin/perl
#
# Copyright (c) 1997-1998 Kevin Johnson <kjj@pobox.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.
#
# $Id: IMSP.pm,v 1.1 1998/12/01 02:13:52 ts Exp $

require 5.004;

package Net::IMSP;

use strict;

use IO::Socket;
use Net::xAP qw($xAP_ATOM $xAP_ASTRING $xAP_PARENS);
use Carp;

use vars qw($VERSION @ISA $SEQUENCE);

@ISA = qw(Net::xAP IO::Socket::INET);

my $Debug = 0;

sub new {
  my $class = shift;
  my $type = ref($class) || $class;
  my $host = shift if @_ % 2;
  my %options = @_;

  $options{Debug} ||= $Debug;

  my $self = Net::xAP->new($host, 'imsp(406)', Timeout => 10, %options)
    or return undef;

  bless $self, $class;

  $self->{Options} = {%options};

  $self->{Banner} = undef;

  STDERR->autoflush(1);

  $self->_get_banner or return undef;

  return $self;
}

sub _get_banner {
  my $self = shift;

  my $list = $self->getline or return undef;

  $self->debug_print(0, join(' ', @{$list})) if $self->debug;

  my $found_it = 0;

  for my $item (@{$list}) {
    if ($item =~ /^imsp$/) {
      $found_it++;
      $last;
    }
  }
  return undef unless ($found_it && ($list->[0] eq '*'));

  $self->{Banner} = join(' ', @{$list});

  return 1;
}

# hide the password from the debug output.
sub debug_text { $_[2] =~ /^(\d+ login [^\s]+)/i ? "$1 ..." : $_[2] }

###############################################################################
sub banner { return shift->{Banner} }
###############################################################################
# capability

# noop

# logout

# authenticate AUTHMECHANISM

# login USERNAME PASSWORD

# create MAILBOXNAME [( SERV/PARTLIST )]

# delete MAILBOXNAME [HOSTNAME]

# rename OLDMAILBOXNAME NEWMAILBOXNAME

# replace OLD MAILBOXNAME NEWMAILBOXNAME

# move MAILBOXNAME ( SERV/PARTLIST )

# subscribe MAILBOXNAME

# unsubscribe MAILBOXNAME

# list REFNAME REGEXMAILBOXNAME

# lsub REFNAME REGEXMAILBOXNAME

# lmarked REFNAME REGEXMAILBOXNAME

# get PATTERN

# set OPTIONNAME NEWVALUE

# unset OPTION

# searchaddress ADDRBOOKNAME LOOKUPCRITERIA

# fetchaddress ADDRBOOKNAME ENTRYNAMES

# deleteaddress ADDRBOOKNAME ENTRYNAME

# addressbook REGEXADDRBOOKNAME

# createaddressbook ADDRBOOKNAME

# deleteaddressbook ADDRBOOKNAME

# renameaddressbook OLDADDRBOOKNAME NEWADDRBOOKNAME

# lock option OPTIONNAME

# unlock option OPTIONNAME

# lock addressbook ADDRBOOKNAME ENTRYNAME

# unlock addressbook ADDRBOOKNAME ADDRBOOKENTRYNAME

# setacl mailbox MAILBOXNAME AUTHIDENTIFIER ACCESSRIGHTS

# setacl addressbook ADDRBOOKNAME AUTHIDENTIFIER ACCESSRIGHTS

# deleteacl mailbox MAILBOXNAME AUTHIDENTIFIER

# deleteacl addressbook ADDRBOOKNAME AITHIDENTIFIER

# getacl mailbox MAILBOXNAME

# getacl addressbook ADDRBOOKNAME

# myrights mailbox MAILBOXNAME

# myrights addressbook ADDRBOOKNAME
###############################################################################
sub generic_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::IMSP::Response->new;
  return sub {
    my $list = shift;
    if ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    }
    return 0;
  }
}
###############################################################################
package Net::IMSP::Response;

use vars qw(@ISA);
@ISA = qw(Net::xAP::Response);

sub parse_status {
  my $self = shift;
  my $list = shift;
  my @list2 = @{$list};

  $self->{Sequence} = shift(@list2);
  $self->{CmdStatus} = uc(shift(@list2));

  my $str = join(' ', @list2);
  $str =~ /^(?:\(([^\)]+)\) )?(.*)$/;
  $self->{StatusCode} = uc($1 || '');
  $self->{StatusText} = $2;
}
###############################################################################

1;
