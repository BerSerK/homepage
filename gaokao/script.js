// 高考日期配置（请修改为实际日期）
const examDates = {
  min: new Date('2027-06-07T09:00:00').getTime(),
  chen: new Date('2040-06-07T09:00:00').getTime(),
  xuan: new Date('2032-06-07T09:00:00').getTime(),
  xinyi: new Date('2038-06-07T09:00:00').getTime(),
  tutu: new Date('2032-06-07T09:00:00').getTime(),
  luo: new Date('2036-06-07T09:00:00').getTime(),
  yao: new Date('2033-06-07T09:00:00').getTime(),
  juntong: new Date('2041-06-07T09:00:00').getTime(),
};

function updateCountdown(id, examDate) {
  const now = new Date().getTime();
  const distance = examDate - now;

  const days = Math.floor(distance / (1000 * 60 * 60 * 24));
  const hours = Math.floor((distance % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
  const minutes = Math.floor((distance % (1000 * 60 * 60)) / (1000 * 60));
  const seconds = Math.floor((distance % (1000 * 60)) / 1000);

  document.getElementById(`${id}-days`).innerText = days;
  document.getElementById(`${id}-hours`).innerText = hours;
  document.getElementById(`${id}-minutes`).innerText = minutes;
  document.getElementById(`${id}-seconds`).innerText = seconds;
}

// 初始更新及每秒更新
Object.keys(examDates).forEach(id => {
  updateCountdown(id, examDates[id]);
  setInterval(() => updateCountdown(id, examDates[id]), 1000);
});
