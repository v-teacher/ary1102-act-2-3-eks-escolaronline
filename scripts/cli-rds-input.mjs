import fs from 'node:fs';
for(const key of ['ACT_NAME','ACT_DB_SG','ACT_DB_PASSWORD'])if(!process.env[key])throw Error('Falta variable '+key);
const e=process.env;
fs.mkdirSync('secrets',{recursive:true,mode:0o700});
fs.writeFileSync('secrets/rds-cli.json',JSON.stringify({DBInstanceIdentifier:e.ACT_NAME,DBInstanceClass:'db.t3.micro',Engine:'mysql',EngineVersion:'8.0.43',AllocatedStorage:20,StorageType:'gp3',MasterUsername:'alumno',MasterUserPassword:e.ACT_DB_PASSWORD,DBName:'escolar_online',DBSubnetGroupName:e.ACT_NAME,VpcSecurityGroupIds:[e.ACT_DB_SG],MultiAZ:true,StorageEncrypted:true,PubliclyAccessible:false,BackupRetentionPeriod:1,Tags:[{Key:'Project',Value:e.ACT_NAME}]}),{mode:0o600});
console.log('JSON privado de RDS preparado. No contiene valores para publicar.');
