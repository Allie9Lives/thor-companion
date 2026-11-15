/** Pure transition rules; initial/catch-up snapshots never produce stale alerts. */
export class BatteryAlerts {
    previous=null;warning=0;
    observe(stats,activity,preferences,now=Date.now()) {
        const priorWarning=this.warning;const result=[],prior=this.previous,level=stats.battery_pct,plugged=!!stats.plugged_code;
        if(!Number.isFinite(level))return result;
        this.previous={level,plugged,at:now};
        if(activity?.warning)this.warning=Math.max(this.warning,activity.warning);
        if(!prior||now-prior.at>5*60000||!preferences.enabled)return result;
        if(preferences.low20&&!plugged&&prior.level>20&&level<=20)result.push({kind:'low20',body:`Battery is at ${Math.round(level)}%.`});
        if(preferences.low10&&!plugged&&prior.level>10&&level<=10)result.push({kind:'low10',body:`Low battery · ${Math.round(level)}% remaining.`});
        if(preferences.charged80&&plugged&&prior.level<80&&level>=80)result.push({kind:'charged80',body:`Charged to ${Math.round(level)}%.`});
        if(preferences.plugged&&!prior.plugged&&plugged)result.push({kind:'plugged',body:'Charger connected.'});
        if(preferences.unplugged&&prior.plugged&&!plugged)result.push({kind:'unplugged',body:`Charger disconnected · ${Math.round(level)}%.`});
        if(preferences.closed&&activity?.lid===true&&activity.closed_s>=600&&activity.warning>priorWarning)result.push({kind:'closed',body:activity.reason||'Activity remains high while the lid is closed.'});
        if(result.some(n=>n.kind==='low10'))return result.filter(n=>n.kind!=='low20');return result;
    }
}
