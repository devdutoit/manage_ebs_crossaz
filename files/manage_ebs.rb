#!/usr/bin/env ruby

require 'aws-sdk'

region      = ARGV[0]
instance_id = ARGV[1]
tag_name    = ARGV[2]
tag_val     = ARGV[3]
device      = ARGV[4]


Aws.config.update({
  region: region,
  credentials: Aws::InstanceProfileCredentials.new,
})


client = Aws::EC2::Client.new
resp = client.describe_instance_status({
  instance_ids: [instance_id],
})

az_id = resp.instance_statuses[0].availability_zone



def create_volume(az_id, volume_id, snap_id)

  if volume_id then

    vol = Aws::EC2::Volume.new(volume_id)

    if vol.availability_zone == az_id then
      return vol.id
    else 
      
      snapshot = vol.create_snapshot({
        description: "ephemeral-snapshot",
      })

      snapshot.wait_until_completed

      client = Aws::EC2::Client.new

      resp = client.create_volume({
        availability_zone: az_id,
        snapshot_id: snapshot.id,
        volume_type: 'gp2',
      })

     
      new_vol = Aws::EC2::Volume.new(resp.volume_id)

      new_vol.create_tags({
        tags: vol.tags,
      })

      sleep 15
      
      vol.create_tags({
        tags: [
        {
          key: vol.tags[0]["key"],
          value: vol.tags[0]["value"]+"-archived",
        },
        ],
      })
      snapshot.delete

      return new_vol.id

    end

  else

    snap = Aws::EC2::Snapshot.new(snap_id)

    client = Aws::EC2::Client.new

    resp = client.create_volume({
      availability_zone: az_id,
      snapshot_id: snap.id,
      volume_type: 'gp2',
    })

    new_vol = Aws::EC2::Volume.new(resp.volume_id)

    new_vol.create_tags({
      tags: snap.tags,
    })  

    sleep 15

    return new_vol.id

  end

end




def get_vol_for_az(az_id, tag_name, tag_val)

  ec2 = Aws::EC2::Resource.new
  volumes = ec2.volumes({
    filters: [
      {
        name: 'tag-key',
        values: [tag_name],
        name:'tag-value',
        values: [tag_val],
        name: 'status',
        values: ['available'],
      }
    ],
  })


  vol_id  = ''
  snap_id = ''

  if volumes.count > 0 then
    volumes.each { |vol| vol_id =  vol.id }
    
    return create_volume(az_id, vol_id, false)
  else
    snapshots = ec2.snapshots({
      filters: [
      {
        name: 'tag-key',
        values: [tag_name],
        name:'tag-value',
        values: [tag_val],
      }
      ],
    })

    snapshots.each { |snap| snap_id = snap.id }

    return create_volume(az_id, false, snap_id)

  end

end


def attach_volume(inst_id, vol_id, dev='/dev/xvdh')

  vol = Aws::EC2::Volume.new(vol_id)
  vol.attach_to_instance({
    instance_id: inst_id,
    device: dev,
  })

end


volume_id = get_vol_for_az(az_id, tag_name, tag_val)

attach_volume(instance_id, volume_id, device)
