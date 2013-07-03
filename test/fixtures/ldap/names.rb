#!/usr/bin/ruby
# encoding: utf-8
# Copyright (C) 2011-2013  The Redmine LDAP Sync Authors
#
# This file is part of Redmine LDAP Sync.
#
# Redmine LDAP Sync is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Redmine LDAP Sync is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Redmine LDAP Sync.  If not, see <http://www.gnu.org/licenses/>.
rng = Random.new(12345)
USERS = 5
GROUPS = 10

puts "dn: dc=redmine,dc=org
objectClass: top
objectClass: dcObject
objectClass: organization
o: redmine.org
dc: redmine

dn: cn=admin,dc=redmine,dc=org
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: admin
description: LDAP administrator
userPassword: {SSHA}Si9/UcgqKWBlN/+SQb+X1IHZnokzaicm

dn: ou=Person,dc=redmine,dc=org
ou: Person
objectClass: organizationalUnit

dn: ou=Group,dc=redmine,dc=org
ou: Group
objectClass: organizationalUnit\n\n"

user =
'dn: uid=%{username},ou=Person,dc=redmine,dc=org
mail: %{mail}
uid: %{username}
cn: %{cn}
preferredLanguage: %{language}
uidNumber: %{uidNumber}
gidNumber: 100
homeDirectory: /home/%{homeDir}
objectClass: posixAccount
objectClass: person
objectClass: inetOrgPerson
givenName: %{givenName}
sn: %{sn}
userPassword: {SSHA}Si9/UcgqKWBlN/+SQb+X1IHZnokzaicm
loginShell: /bin/sh
'

group_member = "member: cn=%{groupname},ou=Group,dc=redmine,dc=org\n"
user_member = "member: uid=%{username},ou=Person,dc=redmine,dc=org\n"
user_group = "o: %{gidNumber}\n"
group_group = "o: %{gidNumber}\n"

group =
'dn: cn=%{groupname},ou=Group,dc=redmine,dc=org
objectClass: groupOfNames
objectClass: posixAccount
homeDirectory: /nonexistent
gidNumber: %{gidNumber}
uidNumber: %{gidNumber}
uid: %{groupname}
cn: %{groupname}
%{members}'

groups = %w(
  Säyeldas	Iardum	Bluil	Anbely	Issekin	Briklør	Enden
  Rynever	Worathest	Therß	Meyl	Oany	Whod	Tiaris
  Belecer	Rill	Strycheser	Ustuq	Issk	Hatosentan	Llant
  Ghaoll	Kimshy	Irenth	Swien	Endash	Denardon	Hatcer
  Aughny	Kibyno	Tonage	Serende	Bietroth	Engech	Aseta
  Tanusk	Umf	Danasho	Rakm	Honeld	Maedtas	Skelmos
  Sulgard	Tonid	Leris	Rothit	Awkin	Sand	Delusk
  Warad	Dihen	Otiao	Therkal	Wage	Emum	Veaw
  Inequa	Lyeack	Agecerat	Achkim	Enrak	Gulut	Oveso
  Toniv	Kalq	Tiaorm	Calltia	Ascerem	Kaltia	Seraufst
  Honibi	Quadeny	Ridasi	Tegh	Teguno	Sewarhat	Poltiaeld
  Polhini	Liwaren	Atler	Tinenhin	Quever	Tanhtor	Nysos
  Brint	Ageaughtor	Lleef	Yiew	Arbche	Perusul	Ghash
  Etum	Itxash	Lamur	Richit	Smuaddan	Fyzin	Endeves
  Iuski	Tinrothu	Lododu	Iuste	Dimyn	Podynen	Lopisy
  Untros	Igara	Emique	Ruperash	Awend	Slyaugh	Ackrandel
  Ustech	Anarr	Ightwor	Aleing	Nyrak	Cheash	Itora
)

users = %w( LoadGeek
tweetmicro
systemhack
tweetsave
microunit
browserclient
webfiber
cabledrive
graphicsfiber
drivechip
iconfiber
corescript
opticipod
blogarray
processipod
waremicro
digiprocess
digiware
iconoptic
scripttweet
clickturtle
ringshark
popsnake
clickowl
tockgiraffe
itchgiraffe
itchdonkey
clickworm
blowgorilla
scratcheagle
yellowcruel
rubycalm
golldhorror
rubyhopeless
blackhappy
whitecross
limegrumpy
lilacgrim
mauvecrrazy
rosemap
leetbroccoli
banana
carrot
winnuts
lolchips
wthfrogs
lmaococonut
winpie
lmaobanana
failcoconut )

names = ['Christián Earheart',
'Rae Croll',
'Darryl Ditto',
'Nelson Meriwether',
'Elnora Gershon',
'Odessa Stingley',
'Kelly Cafferty',
'Dona Austria',
'Ericka Strohl',
'Lakisha Kouba',
'Fernando Dymond',
'Amie Rodreguez',
'Tyrone Winders',
'Rae Degner',
'Darren Canez',
'Earnestine Zahm',
'Fernando Stemm',
'Tanisha Sprowl',
'Saundra Nokes',
'Darren Czerwinski',
'Lenore Messersmith',
'Ashlee Stolz',
'Darryl Schaner',
'Sofia Lacayo',
'Sofia Wiers',
'Lonnie Mccarville',
'Allie Bavaro',
'Sharron Conine',
'Guy Ledger',
'Carmella Kleffman',
'Clayton Rodrick',
'Kathrine Solley',
'Annabelle Riser',
'Julio Wurster',
'Earnestine Camille',
'Hugh Juarbe',
'Guy Hodgin',
'Jamie Alpers',
'Benita Mccrimmon',
'Earnestine Guidroz',
'Ted Formica',
'Jamie Auton',
'Guy Gagnier',
'Tanisha Dahlen',
'Annabelle Spillane',
'Noemi Mcalexander',
'Allan Hynd',
'Fernando Schaner',
'Erik Haubert',
'Jeanie Mazzarella'
]

languages = %w( ar ca de en eu fr hr it lt mn pl ro sl sr-YU tr zh-TWbg cs el es fa gl hu ja lv nl pt-BR ru sq sv uk zhbs da en-GB et fi he id ko mk no pt sk sr th vi )

users = users[0...USERS]
names = names[0...USERS]
groups = groups[0...GROUPS]

s_users = Hash.new{|h,k| h[k] = ''}
s_groups = Hash.new{|h,k| h[k] = ''}

n = 300
users.zip(names).each do |username, fullname|
  s_users[username] = user.
      gsub('%{username}', username).
      gsub('%{cn}', fullname).
      gsub('%{givenName}', fullname.split(' ')[0]).
      gsub('%{sn}', fullname.split(' ')[1]).
      gsub('%{mail}', "#{username.downcase}@fakemail.com").
      gsub('%{uidNumber}', (n += 1).to_s ).
      gsub('%{homeDir}', username).
      gsub('%{language}', languages.sample(:random => rng))
end
n = 4000
groups.each do |groupname|
  gidNumber = (n += 1).to_s
  members = ""
  selected_users = []
  selected_groups = []
  (1..(1+rng.rand(3))).each do |i|
    if rng.rand(2) == 0
      name = (users - selected_users).sample(:random => rng)
      members += user_member.gsub('%{username}', name)
      selected_users << name
      s_users[name] += user_group.gsub('%{gidNumber}', gidNumber)
    else
      name = (groups - selected_groups).sample(:random => rng)
      members += group_member.gsub('%{groupname}', name)
      selected_groups << name
      s_groups[name] += group_group.gsub('%{gidNumber}', gidNumber)
    end
  end
  s_groups[groupname] = group.
      gsub('%{groupname}', groupname).
      gsub('%{gidNumber}', gidNumber).
      gsub('%{members}', members) + s_groups[groupname]
end

# Write everything to stdout
puts s_users.values.join("\n")
puts
puts s_groups.values.join("\n")

puts '
dn: cn=MicroUsers,ou=Group,dc=redmine,dc=org
objectclass: groupOfURLs
cn: MicroUsers
memberURL: ldap:///ou=Person,dc=redmine,dc=org??sub?(uid=*micro*)

dn: cn=TweetUsers,ou=Group,dc=redmine,dc=org
objectclass: groupOfURLs
cn: TweetUsers
memberURL: ldap:///ou=Person,dc=redmine,dc=org??sub?(uid=*tweet*)'
