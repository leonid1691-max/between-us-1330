(()=>{'use strict';
const config=window.BETWEEN_US_CONFIG||{},urlParams=new URLSearchParams(location.search);
let client=null,roomId=urlParams.get('room'),player=urlParams.get('player')==='lenya'?'lenya':'dasha',timer=null,lastError='';
function rowToState(row){if(!row)return;window.BetweenUsGame?.applyRemote({dist:Number(row.distance),index:Number(row.task_index),ready:row.ready_players||[],done:row.history||[],startDate:row.start_date,targetDate:row.target_date})}
function makePlayerUrl(role){const u=new URL(location.href);u.searchParams.set('room',roomId);u.searchParams.set('player',role);return u.href}
async function getRoom(){if(!client||!roomId)return;const {data,error}=await client.rpc('get_game_room',{p_room_id:roomId});if(error)throw error;rowToState(data)}
async function createRoom(){if(!client)throw new Error('Сначала добавьте ключи Supabase в config.js и примените SQL из инструкции.');const {data,error}=await client.rpc('create_game_room');if(error)throw error;roomId=data.room_id;player='lenya';history.replaceState({},'',makePlayerUrl('lenya'));api.inviteUrl=makePlayerUrl('dasha');await getRoom();startPolling();return api.inviteUrl}
function startPolling(){clearInterval(timer);if(!client||!roomId)return;timer=setInterval(async()=>{try{await getRoom();lastError=''}catch(e){if(lastError!==e.message){lastError=e.message;window.BetweenUsGame?.toast('Не удалось обновить общую игру. Проверьте подключение.')}}},2200)}
async function confirm(reward,text){const {data,error}=await client.rpc('confirm_game_step',{p_room_id:roomId,p_player:player,p_reward:reward,p_task:text});if(error)throw error;rowToState(data);return data}
const api={get player(){return player},get room(){return roomId},get enabled(){return !!client},get inviteUrl(){return api._inviteUrl||(roomId?makePlayerUrl('dasha'):location.href)},set inviteUrl(v){api._inviteUrl=v},createRoom,confirm};
window.BetweenUsSync=api;
if(config.supabaseUrl&&config.supabasePublishableKey&&window.supabase?.createClient){client=window.supabase.createClient(config.supabaseUrl,config.supabasePublishableKey,{auth:{persistSession:false,autoRefreshToken:false}});if(roomId){api.inviteUrl=makePlayerUrl('lenya');getRoom().then(startPolling).catch(()=>window.BetweenUsGame?.toast('Комната не найдена. Проверьте ссылку.'))}}
const syncHint=document.querySelector('#syncHint');if(syncHint&&client)syncHint.textContent='Прогресс этой комнаты синхронизируется между устройствами автоматически.';
document.addEventListener('click',async e=>{if(e.target.id==='makeRoom'){e.preventDefault();try{const invite=roomId?makePlayerUrl('dasha'):await createRoom();api.inviteUrl=invite;const share=document.querySelector('#shareText');if(share)share.textContent=invite;e.target.textContent='Ссылка для Даши готова ♡';window.BetweenUsGame?.toast('Комната создана. Скопируйте ссылку и отправьте Даше.')}catch(err){window.BetweenUsGame?.toast(err.message||'Не удалось создать комнату.')}}});
})();
